import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin }    from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import { refreshApex }          from '@salesforce/apex';
import getGroupDetail           from '@salesforce/apex/KenGroupsController.getGroupDetail';
import joinGroup                from '@salesforce/apex/KenGroupsController.joinGroup';
import leaveGroup               from '@salesforce/apex/KenGroupsController.leaveGroup';
import getGroupMembers          from '@salesforce/apex/KenGroupsController.getGroupMembers';
import getPendingRequests       from '@salesforce/apex/KenGroupsController.getPendingRequests';
import getInvitesSent           from '@salesforce/apex/KenGroupsController.getInvitesSent';
import approveJoinRequest       from '@salesforce/apex/KenGroupsController.approveJoinRequest';
import rejectJoinRequest        from '@salesforce/apex/KenGroupsController.rejectJoinRequest';
import removeMember             from '@salesforce/apex/KenGroupsController.removeMember';
import sendInvite               from '@salesforce/apex/KenGroupsController.sendInvite';
import resendInvite             from '@salesforce/apex/KenGroupsController.resendInvite';
import searchAlumniToInvite     from '@salesforce/apex/KenGroupsController.searchAlumniToInvite';
import getEventsForGroup        from '@salesforce/apex/KenGroupsController.getEventsForGroup';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import defaultProfileImage      from '@salesforce/resourceUrl/defaultProfileImage';

export default class KenGroupDetailView extends NavigationMixin(LightningElement) {

    defaultAvatar = defaultProfileImage;

    @track _groupId             = null;
    @track activeTab            = 'About';
    @track isLoading            = true;
    @track _localIsPending      = false;
    @track _localIsJoined       = false;

    @track showLeaveConfirm     = false;
    @track showLeaveSuccess     = false;
    @track isLeaving            = false;
    @track isJoining            = false;

    @track membersList          = [];
    @track membersLoading       = false;
    @track groupEvents          = [];
    @track eventsLoading        = false;
    @track eventsLoaded         = false;
    @track pendingRequests      = [];
    @track requestsLoading      = false;
    @track invitesSent          = [];
    @track invitesLoading       = false;
    @track adminPanelTab        = 'requests';
    @track showInvitesSentModal = false;

    @track showInviteModal      = false;
    @track inviteSearchTerm     = '';
    @track inviteSearchResults  = [];
    @track inviteSearchLoading  = false;
    @track invitingAccountId    = null;
    _inviteSearchTimer          = null;

    @track showAllMembersModal        = false;
    @track showPendingRequestsModal   = false;
    @track allPendingRequests         = [];

    // Invite email chips
    @track inviteEmails               = [];
    @track currentEmailInput          = '';

    @track toastVisible         = false;
    @track toastTitle           = '';
    @track toastMessage         = '';
    @track toastVariant         = 'success';
    @track actionLoading        = false;

    _wiredGroupDetailResult = null;
    _pendingDeepLinkTab = null;

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (pageRef?.state) {
            const id = pageRef.state.c__groupId || pageRef.state.groupId || null;
            this._pendingDeepLinkTab = pageRef.state.c__tab || pageRef.state.tab || null;
            if (id !== this._groupId) {
                this._groupId        = id;
                this._localIsPending = false;
                this._localIsJoined  = false;
                this.activeTab       = 'About';
                this.isLoading       = true;
                this.membersList     = [];
                this.pendingRequests = [];
                this.invitesSent     = [];
            }
        }
    }

    @wire(getGroupDetail, { groupId: '$_groupId' })
    wiredGroupDetail(result) {
        this._wiredGroupDetailResult = result;
        if (result.data || result.error) this.isLoading = false;
        this._applyPendingDeepLinkTab();
    }

    _applyPendingDeepLinkTab() {
        if (!this._pendingDeepLinkTab || !this.groupData) return;
        const tab = this._pendingDeepLinkTab;
        if (tab === 'requests' && this.isAdmin) {
            this._pendingDeepLinkTab = null;
            this.adminPanelTab = 'requests';
            this.openMembersTab();
        }
    }

    get groupData() { return this._wiredGroupDetailResult?.data || null; }

    get membershipStatus() {
        const d = this.groupData;
        if (!d) return 'none';
        if (d.isCreated) return 'admin';
        if (d.isJoined  || this._localIsJoined)  return 'member';
        if (d.isPending || this._localIsPending) return 'pending';
        return 'none';
    }

    get isAccessible() { return this.membershipStatus === 'member' || this.membershipStatus === 'admin'; }
    get isAdmin()      { return this.membershipStatus === 'admin'; }
    get isNone()       { return this.membershipStatus === 'none'; }
    get isPending()    { return this.membershipStatus === 'pending'; }
    get isJoined()     { return this.isAccessible; }
    get isPublicGroup(){ return this.groupData?.isPublic === true || this.groupData?.groupType === 'Public'; }

    get groupName()        { return this.groupData?.name        || ''; }
    get groupDescription() { return this.groupData?.description || ''; }
    get groupRules()       { return this.groupData?.rules       || ''; }
    get groupType()        { return this.groupData?.groupType   || 'Private'; }
    get groupCategory()    { return this.groupData?.category    || ''; }
    get membersCountText() { return this.groupData?.memberCountFormatted || '0'; }
    get createdByName()        { return this.groupData?.createdByName || 'Admin'; }
    get createdByPhotoUrl()    { return this.groupData?.createdByPhotoUrl || this.defaultAvatar; }
    get createdDateLabel() { return this.groupData?.createdDate   || ''; }
    get hasDescription()   { return !!this.groupData?.description; }
    get hasRules()         { return !!this.groupData?.rules; }

    get tagsList() {
        const tags = this.groupData?.tags;
        if (!tags) return [];
        return tags.split(',').map((t, i) => ({ id: i, label: t.trim() })).filter(t => t.label);
    }
    get hasTags() { return this.tagsList.length > 0; }

    get bannerStyle() {
        const d = this.groupData;
        if (!d) return '';
        return this._getCardStyle(d.bannerImage, d.category);
    }

    _getCardStyle(bannerImage, category) {
        const gradients = {
            Professional: 'linear-gradient(135deg, #1a237e 0%, #1565c0 100%)',
            Sports:       'linear-gradient(135deg, #1b5e20 0%, #388e3c 100%)',
            Batch:        'linear-gradient(135deg, #4a148c 0%, #7b1fa2 100%)',
            Interest:     'linear-gradient(135deg, #bf360c 0%, #e64a19 100%)',
            Academic:     'linear-gradient(135deg, #01579b 0%, #0288d1 100%)',
            Social:       'linear-gradient(135deg, #880e4f 0%, #c2185b 100%)',
            Other:        'linear-gradient(135deg, #263238 0%, #546e7a 100%)'
        };
        const gradient = gradients[category] || gradients.Other;
        return bannerImage
            ? `background: url('${bannerImage}') center/cover no-repeat, ${gradient};`
            : `background: ${gradient};`;
    }

    get showFooterAdminAboutButtons()   { return this.isAdmin && this.activeTab === 'About'; }
    get showFooterAdminMembersButtons() { return this.isAdmin && this.activeTab === 'Members'; }
    get showFooterAdminEventsButtons()  { return this.isAdmin && this.activeTab === 'Events'; }

    get showAbout()   { return this.activeTab === 'About'; }
    get showFeed()    { return this.activeTab === 'Feed'    && this.isAccessible; }
    get showEvents()  { return this.activeTab === 'Events'  && this.isAccessible; }
    get showMembers() { return this.activeTab === 'Members' && this.isAdmin; }
    get showMembersTab() { return this.isAdmin; }

    get tabAboutClass()   { return `tab${this.activeTab === 'About'   ? ' active' : ''}`; }
    get tabFeedClass()    { return `tab${this.activeTab === 'Feed'    ? ' active' : ''}`; }
    get tabEventsClass()  { return `tab${this.activeTab === 'Events'  ? ' active' : ''}`; }
    get tabMembersClass() { return `tab${this.activeTab === 'Members' ? ' active' : ''}`; }

    get adminTabRequestsClass() { return `admin-tab${this.adminPanelTab === 'requests' ? ' active' : ''}`; }
    get adminTabInvitesClass()  { return `admin-tab${this.adminPanelTab === 'invites'  ? ' active' : ''}`; }
    get showRequestsPanel()     { return this.adminPanelTab === 'requests'; }
    get showInvitesPanel()      { return this.adminPanelTab === 'invites'; }

    openAboutTab()   { this.activeTab = 'About'; }
    openFeedTab()    { if (this.isAccessible) this.activeTab = 'Feed'; }
    openEventsTab()  {
        if (!this.isAccessible) return;
        this.activeTab = 'Events';
        this._loadGroupEvents();
    }

    get hasGroupEvents() { return Array.isArray(this.groupEvents) && this.groupEvents.length > 0; }
    get showEventsEmpty() { return !this.eventsLoading && this.eventsLoaded && !this.hasGroupEvents; }

    _loadGroupEvents() {
        if (!this._groupId) return;
        this.eventsLoading = true;
        getEventsForGroup({ groupId: this._groupId })
            .then(data => {
                this.groupEvents = (data || []).map(ev => ({
                    ...ev,
                    bannerImage: ev.bannerImage || this.defaultAvatar,
                    hasLocation: !!ev.location,
                    hasTime: !!ev.timeLabel,
                    eventTagLabel: ev.eventType || 'Event'
                }));
            })
            .catch(() => { this.groupEvents = []; })
            .finally(() => {
                this.eventsLoading = false;
                this.eventsLoaded = true;
            });
    }

    handleEventCardClick(event) {
        const eventId = event.currentTarget?.dataset?.eventId;
        if (!eventId) return;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'event_detail__c' },
            state: { recordId: eventId }
        });
    }
    openMembersTab() {
        if (!this.isAccessible) return;
        this.activeTab = 'Members';
        this._loadMembersData();
    }
    openRequestsPanel() { this.adminPanelTab = 'requests'; }
    openInvitesPanel()  { this.adminPanelTab = 'invites'; this._loadInvitesSent(); }

    _loadMembersData() {
        if (!this._groupId) return;
        this.membersLoading = true;
        getGroupMembers({ groupId: this._groupId })
            .then(data => { this.membersList = this._mapMembers(data); })
            .catch(() => { this._showToast('error', 'Error', 'Failed to load members.'); })
            .finally(() => { this.membersLoading = false; });
        if (this.isAdmin) {
            this._loadPendingRequests();
            this._loadInvitesSent();
        }
    }

    _loadPendingRequests() {
        this.requestsLoading = true;
        getPendingRequests({ groupId: this._groupId })
            .then(data => {
                this.pendingRequests = this._mapMembers(data);
                this.allPendingRequests = [...this.pendingRequests];
            })
            .catch(() => {})
            .finally(() => { this.requestsLoading = false; });
    }

    _loadInvitesSent() {
        this.invitesLoading = true;
        getInvitesSent({ groupId: this._groupId })
            .then(data => { this.invitesSent = this._mapMembers(data); })
            .catch(() => {})
            .finally(() => { this.invitesLoading = false; });
    }

    _mapMembers(data) {
        return (data || []).map(m => ({
            ...m,
            photoUrl: m.photoUrl || this.defaultAvatar,
            isInviteDeclined: m.status === 'Invite Declined'
        }));
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            if (color) {
                document.documentElement.style.setProperty('--primary-color', color.primaryColor);
                document.documentElement.style.setProperty('--secondary-color', color.secondaryColor);
                document.documentElement.style.setProperty('--tertiary-color', color.tertiaryColor);
            }
        }).catch(() => {});
    }

    handleBack() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'group__c' } });
    }

    handleJoin() {
        if (!this._groupId || this.isJoining) return;
        this.isJoining = true;
        joinGroup({ groupId: this._groupId })
            .then(() => {
                if (this.isPublicGroup) {
                    this._localIsJoined  = true;
                    this._showToast('success', 'Joined!', 'You have successfully joined the group.');
                } else {
                    this._localIsPending = true;
                    this._showToast('success', 'Request Sent!', 'The admin will review your request.');
                }
                return refreshApex(this._wiredGroupDetailResult);
            })
            .catch(err => {
                this._showToast('error', 'Error', err?.body?.message || 'Failed to join group.');
            })
            .finally(() => { this.isJoining = false; });
    }

    handleLeave()  { this.showLeaveConfirm = true; }
    cancelLeave()  { this.showLeaveConfirm = false; }

    confirmLeave() {
        const memberRecordId = this.groupData?.memberRecordId;
        if (!memberRecordId || this.isLeaving) return;
        this.isLeaving        = true;
        this.showLeaveConfirm = false;
        leaveGroup({ memberRecordId })
            .then(() => {
                this.showLeaveSuccess = true;
                this._localIsJoined  = false;
                this._localIsPending = false;
                return refreshApex(this._wiredGroupDetailResult);
            })
            .then(() => {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => { this.showLeaveSuccess = false; this.handleBack(); }, 1500);
            })
            .catch(err => {
                this._showToast('error', 'Error', err?.body?.message || 'Failed to leave group.');
            })
            .finally(() => { this.isLeaving = false; });
    }

    handleApproveRequest(event) {
        const memberRecordId = event.currentTarget.dataset.memberRecordId;
        if (!memberRecordId) return;
        this.actionLoading = true;
        approveJoinRequest({ memberRecordId })
            .then(() => {
                this.pendingRequests = this.pendingRequests.filter(m => m.memberRecordId !== memberRecordId);
                this._showToast('success', 'Approved', 'Member request approved.');
                this._loadMembersData();
                return refreshApex(this._wiredGroupDetailResult);
            })
            .catch(err => { this._showToast('error', 'Error', err?.body?.message || 'Failed to approve.'); })
            .finally(() => { this.actionLoading = false; });
    }

    handleRejectRequest(event) {
        const memberRecordId = event.currentTarget.dataset.memberRecordId;
        if (!memberRecordId) return;
        this.actionLoading = true;
        rejectJoinRequest({ memberRecordId })
            .then(() => {
                this.pendingRequests = this.pendingRequests.filter(m => m.memberRecordId !== memberRecordId);
                this._showToast('success', 'Rejected', 'Member request rejected.');
            })
            .catch(err => { this._showToast('error', 'Error', err?.body?.message || 'Failed to reject.'); })
            .finally(() => { this.actionLoading = false; });
    }

    handleRemoveMember(event) {
        const memberRecordId = event.currentTarget.dataset.memberRecordId;
        if (!memberRecordId) return;
        this.actionLoading = true;
        removeMember({ memberRecordId })
            .then(() => {
                this.membersList = this.membersList.filter(m => m.memberRecordId !== memberRecordId);
                this._showToast('success', 'Removed', 'Member removed from group.');
                return refreshApex(this._wiredGroupDetailResult);
            })
            .catch(err => { this._showToast('error', 'Error', err?.body?.message || 'Failed to remove.'); })
            .finally(() => { this.actionLoading = false; });
    }

    handleOpenInviteModal() {
        this.showInviteModal     = true;
        this.inviteSearchTerm    = '';
        this.inviteSearchResults = [];
        this.inviteEmails        = [];
        this.currentEmailInput   = '';
    }
    handleCloseInviteModal() {
        this.showInviteModal     = false;
        this.inviteSearchTerm    = '';
        this.inviteSearchResults = [];
        this.inviteEmails        = [];
        this.currentEmailInput   = '';
    }

    handleEmailInputChange(event) {
        this.currentEmailInput = event.target.value;
    }

    handleEmailKeyDown(event) {
        if (event.key === 'Enter' && this.currentEmailInput.trim()) {
            event.preventDefault();
            const val = this.currentEmailInput.trim();
            if (!this.inviteEmails.includes(val)) {
                this.inviteEmails = [...this.inviteEmails, val];
            }
            this.currentEmailInput = '';
            event.target.value = '';

            this.inviteSearchLoading = true;
            searchAlumniToInvite({ groupId: this._groupId, searchTerm: val })
                .then(data => { this.inviteSearchResults = (data || []).map(r => ({ ...r, photoUrl: r.photoUrl || this.defaultAvatar })); })
                .catch(() => {})
                .finally(() => { this.inviteSearchLoading = false; });
        }
    }

    handleRemoveEmailChip(event) {
        const idx = parseInt(event.currentTarget.dataset.idx, 10);
        this.inviteEmails = this.inviteEmails.filter((_, i) => i !== idx);
    }

    get emailChipsList() {
        return this.inviteEmails.map((e, i) => ({ id: i, label: e }));
    }

    handleInviteSearch(event) {
        this.inviteSearchTerm = event.target.value;
        clearTimeout(this._inviteSearchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._inviteSearchTimer = setTimeout(() => {
            this.inviteSearchLoading = true;
            searchAlumniToInvite({ groupId: this._groupId, searchTerm: this.inviteSearchTerm })
                .then(data => {
                    this.inviteSearchResults = (data || []).map(r => ({
                        ...r,
                        photoUrl: r.photoUrl || this.defaultAvatar
                    }));
                })
                .catch(() => {})
                .finally(() => { this.inviteSearchLoading = false; });
        }, 300);
    }

    handleSendInvite(event) {
        const accountId = event.currentTarget.dataset.accountId;
        if (!accountId || this.invitingAccountId) return;
        this.invitingAccountId = accountId;
        sendInvite({ groupId: this._groupId, accountId })
            .then(() => {
                this.inviteSearchResults = this.inviteSearchResults.filter(r => r.accountId !== accountId);
                this._showToast('success', 'Invited', 'Invitation sent successfully.');
                this._loadInvitesSent();
            })
            .catch(err => { this._showToast('error', 'Error', err?.body?.message || 'Failed to send invite.'); })
            .finally(() => { this.invitingAccountId = null; });
    }

    handleSendInvites() {
        if (!this.inviteSearchResults.length && !this.inviteEmails.length) return;
        const toInvite = this.inviteSearchResults.slice();
        if (!toInvite.length) {
            this._showToast('info', 'No Results', 'No alumni found to invite. Try searching by name.');
            return;
        }
        this.actionLoading = true;
        const promises = toInvite.map(r => sendInvite({ groupId: this._groupId, accountId: r.accountId }));
        Promise.allSettled(promises).then(results => {
            const succeeded = results.filter(r => r.status === 'fulfilled').length;
            this._showToast('success', 'Invites Sent', `${succeeded} invitation(s) sent.`);
            this.handleCloseInviteModal();
            this._loadInvitesSent();
        }).finally(() => { this.actionLoading = false; });
    }

    handleResendInvite(event) {
        const memberRecordId = event.currentTarget.dataset.memberRecordId;
        if (!memberRecordId) return;
        this.actionLoading = true;
        resendInvite({ memberRecordId })
            .then(() => {
                this._showToast('success', 'Resent', 'Invitation resent.');
                this._loadInvitesSent();
            })
            .catch(err => { this._showToast('error', 'Error', err?.body?.message || 'Failed to resend.'); })
            .finally(() => { this.actionLoading = false; });
    }

    handleOpenInvitesSentModal()  { this.showInvitesSentModal = true; }
    handleCloseInvitesSentModal() { this.showInvitesSentModal = false; }

    handleOpenMembersModal() {
        if (!this.membersList.length && !this.membersLoading && this._groupId) {
            this._loadMembersData();
        }
        this.showAllMembersModal = true;
    }
    handleCloseMembersModal() { this.showAllMembersModal = false; }

    handleOpenPendingModal() {
        if (!this.allPendingRequests.length) this.allPendingRequests = [...this.pendingRequests];
        this.showPendingRequestsModal = true;
    }
    handleClosePendingModal() { this.showPendingRequestsModal = false; }

    handleEditGroup() {
        sessionStorage.setItem('createGroupDraftId', this._groupId);
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'create_group__c' } });
    }

    // Launch the Host Event wizard as a fresh event with THIS group pre-selected as
    // the target audience. Only the group id is passed in the URL (?preselectGroupId=…);
    // the wizard resolves the name + member count from it. No sessionStorage, so a later
    // "Host Event" entry (no param) can't inherit a stale group. Still clear any
    // in-progress draft so the wizard starts fresh.
    handleCreateEvent() {
        try { sessionStorage.removeItem('currentEventId'); } catch (e) { /* ignore */ }
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'host_event__c' },
            state: { preselectGroupId: this._groupId }
        });
    }

    handleCopyInviteLink() {
        const url = window.location.href;
        if (navigator.clipboard) {
            navigator.clipboard.writeText(url)
                .then(() => this._showToast('success', 'Copied!', 'Invite link copied to clipboard.'))
                .catch(() => this._showToast('error', 'Error', 'Failed to copy link.'));
        } else {
            this._showToast('error', 'Error', 'Clipboard not supported in this browser.');
        }
    }

    _showToast(variant, title, message) {
        this.toastVariant = variant;
        this.toastTitle   = title;
        this.toastMessage = message;
        this.toastVisible = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.toastVisible = false; }, 3500);
    }

    stopPropagation(event) { event.stopPropagation(); }
}