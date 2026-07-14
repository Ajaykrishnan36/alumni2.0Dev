// V2 wiring — calls OLD KenMentorshipController. Do not modify the OLD controller.
// If a DTO shape mismatch breaks rendering, fix it in this file's mapDto(), not in the controller.
// Imperative calls (not @wire) for consistency. Mock data below stays as fallback.
import { LightningElement, track } from 'lwc';
import getMentorshipConnections from '@salesforce/apex/KenMentorshipController.getMentorshipConnections';
import getAcceptedMentorsForCurrentMentee from '@salesforce/apex/KenMentorshipController.getAcceptedMentorsForCurrentMentee';
import getTasksForCurrentMentee from '@salesforce/apex/KenMentorshipController.getTasksForCurrentMentee';
import scheduleCallForCurrentMentee from '@salesforce/apex/KenMentorshipController.scheduleCallForCurrentMentee';
import saveTaskForCurrentMentee from '@salesforce/apex/KenMentorshipController.saveTaskForCurrentMentee';
import deleteTaskForCurrentMentee from '@salesforce/apex/KenMentorshipController.deleteTaskForCurrentMentee';
import respondToCallRequest from '@salesforce/apex/KenMentorshipController.respondToCallRequest';
import getScheduledCallsForCurrentMentee from '@salesforce/apex/KenMentorshipController.getScheduledCallsForCurrentMentee';

const SF_ID_RE_M = /^[a-zA-Z0-9]{15,18}$/;
const isSfIdM = (v) => typeof v === 'string' && SF_ID_RE_M.test(v);

// Shared helpers (mirrored from kenNetworkPageV2 — keep signatures identical so child usage stays uniform).
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
const asBoolM = (v) => v === true || v === 'true';

const MENTOR_PALETTE = ['#E6BFA1','#F4C2C2','#C8B6FF','#FFD6A5','#E8B4D6','#67A1C8'];

// All mock mentor/review/availability/tasks/sessions arrays removed.
// Page renders empty state until KenMentorshipController returns real data.
const DEFAULT_TASKS = [];
const SESSIONS = [];

export default class KenMentorshipV2 extends LightningElement {
    @track activeView = 'landing';
    @track activeTab = 'connections';
    @track selectedMentorId = 0;
    @track tasks = JSON.parse(JSON.stringify(DEFAULT_TASKS));
    @track showAddTask = false;
    @track newTaskTitle = '';
    @track newTaskDesc = '';
    @track newTaskPriority = 'Medium';
    @track toastVisible = false;
    @track toastMessage = '';
    @track currentMonth = new Date();
    _toastTimer = null;

    formatMonthYear(d) {
        if (!d || !(d instanceof Date) || isNaN(d.getTime())) return '';
        return d.toLocaleDateString('en-IN', { month: 'long', year: 'numeric' });
    }
    get currentMonthYearLabel() { return this.formatMonthYear(this.currentMonth); }

    // Allows the calendar child to bubble up month nav so the header stays in sync.
    handleCalendarMonthChange(event) {
        const d = event && event.detail && event.detail.date;
        if (d instanceof Date && !isNaN(d.getTime())) {
            this.currentMonth = d;
        } else if (typeof d === 'string') {
            const parsed = new Date(d);
            if (!isNaN(parsed.getTime())) this.currentMonth = parsed;
        }
    }

    /* ===== OLD Apex wiring =====
       Start empty + loading so no mock flash; mock only on Apex error. */
    @track mentorsState = [];
    @track isLoading = true;
    @track tasksState = null; // null = use local mock tasks
    @track callRequests = [];
    @track mentorshipError = null;

    connectedCallback() {
        try {
            const params = new URLSearchParams(window.location.search);
            const tab = params.get('tab');
            const view = params.get('view');
            const id = params.get('id');
            const VALID_TABS = ['connections', 'mentees', 'tasks', 'sessions'];
            const VALID_VIEWS = ['landing', 'profile', 'scheduleCall', 'scheduleList'];
            if (tab && VALID_TABS.indexOf(tab) > -1) this.activeTab = tab;
            if (view && VALID_VIEWS.indexOf(view) > -1) this.activeView = view;
            if (id) this.selectedMentorId = /^\d+$/.test(id) ? Number(id) : id;
        } catch (e) { /* ignore */ }
        this.loadMentorship();
        this.loadTasks();
        this.loadCallRequests();
    }

    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            if (this.activeTab) params.set('tab', this.activeTab); else params.delete('tab');
            if (this.activeView && this.activeView !== 'landing') params.set('view', this.activeView); else params.delete('view');
            if (this.selectedMentorId) params.set('id', String(this.selectedMentorId)); else params.delete('id');
            const qs = params.toString();
            window.history.replaceState(null, '', window.location.pathname + (qs ? '?' + qs : ''));
        } catch (e) { /* ignore */ }
    }

    loadCallRequests() {
        getScheduledCallsForCurrentMentee()
            .then(rows => {
                if (!Array.isArray(rows)) return;
                this.callRequests = rows
                    .filter(r => {
                        const s = (r && r.callRequestStatus ? String(r.callRequestStatus) : '').toLowerCase();
                        return s === 'pending' || s === 'requested' || s === 'awaiting approval';
                    })
                    .map(r => ({
                        id: r.id,
                        title: r.title || 'Mentorship Call',
                        requester: r.requesterName || r.mentor || '',
                        role: r.counterpartTitle || '',
                        dateIso: r.dateIso || '',
                        // Pre-formatted display string. Template should bind {c.dateLabel} not {c.dateIso}.
                        dateLabel: formatDate(r.dateIso, false),
                        timeLabel: r.timeLabel || '',
                        agenda: r.meetingDescription || r.topic || '',
                        status: r.callRequestStatus || 'Pending'
                    }));
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMentorshipController.getScheduledCallsForCurrentMentee error', err);
            });
    }

    get hasCallRequests() { return this.callRequests && this.callRequests.length > 0; }

    loadMentorship() {
        this.isLoading = true;
        let hadError = false;
        Promise.all([
            getMentorshipConnections().catch(err => { hadError = true; this.mentorshipError = err; return null; }),
            getAcceptedMentorsForCurrentMentee().catch(err => { hadError = true; this.mentorshipError = err; return null; })
        ]).then(([connRows, mentorOpts]) => {
            if (hadError && connRows == null) {
                // Apex failed — show empty state, no mock flash.
                this.mentorsState = [];
                // eslint-disable-next-line no-console
                console.error('KenMentorshipController error', this.mentorshipError);
            } else {
                this.mentorsState = this.mapMentors(connRows || [], mentorOpts || []);
                this.mentorshipError = null;
            }
            this.isLoading = false;
        });
    }

    get hasMentors() { return (this.mentorsState || []).length > 0; }
    get showMentorsEmpty() { return !this.isLoading && !this.hasMentors && !this.mentorshipError; }

    loadTasks() {
        getTasksForCurrentMentee()
            .then(rows => {
                if (Array.isArray(rows) && rows.length) {
                    this.tasksState = rows.map((t, i) => ({
                        id: t.id || i + 1,
                        title: t.title || '',
                        desc: t.description || '',
                        priority: t.priority || 'Medium',
                        status: (t.status || '').toLowerCase().indexOf('done') >= 0 || (t.status || '').toLowerCase() === 'completed' ? 'done' : 'progress'
                    }));
                    this.tasks = this.tasksState;
                }
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMentorshipController.getTasksForCurrentMentee error', err);
            });
    }

    // Translate OLD MentorshipConnectionRow[] + MentorOption[] → existing MENTORS shape.
    mapMentors(connRows, mentorOpts) {
        const out = [];
        const acceptedIds = new Set();
        (mentorOpts || []).forEach(o => { if (o && o.value) acceptedIds.add(o.value); });

        (connRows || []).forEach((r, i) => {
            if (!r) return;
            const isMentorRel = r.currentUserIsMentor === false; // counterpart is a mentor
            const tag = isMentorRel ? 'Mentor' : 'Mentee';
            out.push({
                id: r.personAccountId || r.id || i + 1,
                mentorshipId: r.mentorshipId,
                name: r.name || '',
                role: r.title || r.jobFunction || '',
                company: r.company || '',
                city: r.location || r.currentCity || '',
                tag,
                initial: (r.name || ' ').charAt(0).toUpperCase(),
                color: MENTOR_PALETTE[i % MENTOR_PALETTE.length],
                verified: asBoolM(r.willingToHelp),
                bio: '',
                rating: 0,
                sessions: 0,
                sessionsHeld: '0',
                responseRate: '—',
                experience: '',
                batch: r.graduationYear ? 'Batch of ' + r.graduationYear : '',
                languages: '',
                expertise: [r.industry, r.specialisation, r.programLastAttended].filter(Boolean),
                reviews: [],
                availability: [], // populated by schedule wizard via getMentorAvailabilityDays
                priceLabel: 'Free',
                sessionLength: '30 min default',
                profileImage: safeImg(r.profileImage),
                mentorshipStatus: r.mentorshipStatus,
                callRequestStatus: r.callRequestStatus
            });
        });
        return out;
    }

    get isLanding()      { return this.activeView === 'landing'; }
    get isProfile()      { return this.activeView === 'profile'; }
    get isScheduleCall() { return this.activeView === 'scheduleCall'; }
    get isScheduleList() { return this.activeView === 'scheduleList'; }

    // Router state — purely about which view is rendered (board vs profile/wizard/list). Mutually exclusive.
    get viewState() {
        return {
            isBoard:         this.activeView === 'landing',
            isProfile:       this.activeView === 'profile',
            isScheduleCall:  this.activeView === 'scheduleCall',
            isScheduleList:  this.activeView === 'scheduleList'
        };
    }
    // Tab state lives separately so getters don't conflate "which tab" with "which view".
    get tabState() {
        return {
            isConnections: this.activeTab === 'connections',
            isMentees:     this.activeTab === 'mentees',
            isTasks:       this.activeTab === 'tasks',
            isSessions:    this.activeTab === 'sessions'
        };
    }

    get isConnectionsTab() { return this.activeTab === 'connections'; }
    get isMenteesTab()     { return this.activeTab === 'mentees'; }
    get isTasksTab()       { return this.activeTab === 'tasks'; }
    get isSessionsTab()    { return this.activeTab === 'sessions'; }
    get hasMentees()       { return this.mentees.length > 0; }
    get hasSessions()      { return (this.sessions || []).length > 0; }
    get hasTasks()         { return (this.tasks || []).length > 0; }

    get mentors() { return this.mentorsState; }
    get mentees() { return this.mentorsState.filter(m => m.tag === 'Mentee'); }
    get sessions() { return SESSIONS; }

    get selectedMentor() {
        return this.mentorsState.find(x => x.id === this.selectedMentorId) || null;
    }

    handleTabChange(event) { this.activeTab = event.detail.id; this.syncUrl(); }
    handleMentorClick(event) {
        const raw = event.detail && event.detail.id;
        if (raw === undefined || raw === null) return;
        const id = typeof raw === 'string' && !/^\d+$/.test(raw) ? raw : Number(raw);
        if (!id && id !== 0) return;
        this._scrollY = (typeof window !== 'undefined' && window.scrollY) || 0;
        this.selectedMentorId = id;
        this.activeView = 'profile';
        this.syncUrl();
        try { window.scrollTo({ top: 0, behavior: 'instant' }); } catch (e) { window.scrollTo(0, 0); }
    }
    _restoreScroll() {
        const y = this._scrollY || 0;
        try { requestAnimationFrame(() => { try { window.scrollTo(0, y); } catch (e) { /* ignore */ } }); }
        catch (e) { try { window.scrollTo(0, y); } catch (_) { /* ignore */ } }
    }
    handleBackToBoard() {
        this.activeView = 'landing';
        this.selectedMentorId = 0;
        this.syncUrl();
        this._restoreScroll();
    }
    handleCloseProfile() {
        this.activeView = 'landing';
        this.selectedMentorId = 0;
        this.syncUrl();
        this._restoreScroll();
    }
    handleBookFromProfile(event) {
        const raw = event.detail && event.detail.id;
        this.selectedMentorId = typeof raw === 'string' && !/^\d+$/.test(raw) ? raw : Number(raw);
        this.activeView = 'scheduleCall';
        this.syncUrl();
    }
    handleMessageFromProfile() { this._toast('Opening chat…'); }
    handleOpenSchedule() { this.activeView = 'scheduleCall'; this.syncUrl(); }
    handleCloseSchedule() { this.activeView = 'landing'; this.syncUrl(); }
    handleScheduleConfirm(event) {
        const d = (event && event.detail) || {};
        // QA Bug #128 — accept mentorId from the wizard's confirm event (picker-mode
        // path) AND fall back to the parent's pre-selected mentor. The previous code
        // ONLY looked at this.selectedMentor, so when the wizard opened without a
        // pre-selected mentor and the user picked one inside the picker, that pick
        // was silently discarded and Apex got mentorId=null → "Please select a mentor."
        const SF_ID = /^[a-zA-Z0-9]{15,18}$/;
        const fromDetail   = d.mentorId && SF_ID.test(String(d.mentorId)) ? d.mentorId : null;
        const mentor       = this.selectedMentor;
        const fromSelected = mentor && typeof mentor.id === 'string' && !/^\d+$/.test(mentor.id) ? mentor.id : null;
        const mentorId     = fromDetail || fromSelected;
        // Only fire the Apex call when we have a real Salesforce mentor Id; otherwise treat as mock.
        if (mentorId) {
            const request = {
                mentorId,
                selectedMentor: mentorId,
                mentorValue: mentorId,
                participantType: 'mentor',
                title: d.topic || d.title || 'Mentorship Session',
                // Wizard now emits machine-readable startTime/endTime/meetingDate;
                // fall back to the human-readable fields for backward compatibility.
                meetingDate: d.meetingDate || d.date || '',
                startTime: d.startTime || d.slot || '',
                endTime: d.endTime || '',
                description: d.agenda || d.description || '',
                meetingType: d.meetingType || 'Online'
            };
            scheduleCallForCurrentMentee({ request })
                .then(() => {
                    this.activeView = 'landing';
                    this.syncUrl();
                    this._toast('Booking request sent');
                })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('KenMentorshipController.scheduleCallForCurrentMentee error', err);
                    this.activeView = 'landing';
                    this.syncUrl();
                    this._toast((err && err.body && err.body.message) || 'Could not send booking request');
                });
        } else {
            this.activeView = 'landing';
            this.syncUrl();
            this._toast('Please pick a mentor before scheduling.');
        }
    }
    handleOpenScheduleList() { this.activeView = 'scheduleList'; this.syncUrl(); }
    handleBackToLanding() { this.activeView = 'landing'; this.syncUrl(); }
    handleOpenPreferences() { this._toast('Opening preferences…'); }

    handleAddTaskOpen() {
        this.showAddTask = true;
        this.newTaskTitle = '';
        this.newTaskDesc = '';
        this.newTaskPriority = 'Medium';
    }
    handleAddTaskClose() { this.showAddTask = false; }
    handleTaskTitle(event) { this.newTaskTitle = event.target.value; }
    handleTaskDesc(event) { this.newTaskDesc = event.target.value; }
    handleTaskPriority(event) { this.newTaskPriority = event.target.value; }
    handleAddTaskSubmit() {
        const title = (this.newTaskTitle || '').trim();
        if (!title) return;
        const tempId = Date.now();
        const optimistic = { id: tempId, title, desc: this.newTaskDesc || 'Newly added task.', priority: this.newTaskPriority, status: 'progress' };
        this.tasks = [optimistic, ...this.tasks];
        this.showAddTask = false;
        this.activeTab = 'tasks';
        this.syncUrl();
        const request = {
            title,
            description: this.newTaskDesc || '',
            descriptionHtml: this.newTaskDesc || '',
            priority: this.newTaskPriority || 'Medium',
            status: 'In Progress'
        };
        saveTaskForCurrentMentee({ request })
            .then(saved => {
                if (saved && saved.id) {
                    this.tasks = this.tasks.map(t => t.id === tempId ? { ...t, id: saved.id } : t);
                }
                this._toast('Task added');
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMentorshipController.saveTaskForCurrentMentee error', err);
                this._toast('Task added (offline)');
            });
    }
    handleDeleteTask(event) {
        const raw = event && event.detail && event.detail.id;
        const id = raw == null ? null : (typeof raw === 'string' && !/^\d+$/.test(raw) ? raw : Number(raw));
        const prev = this.tasks;
        this.tasks = this.tasks.filter(t => t.id !== id);
        if (!isSfIdM(id)) { this._toast('Task removed'); return; }
        deleteTaskForCurrentMentee({ taskId: id })
            .then(() => { this._toast('Task removed'); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMentorshipController.deleteTaskForCurrentMentee error', err);
                this.tasks = prev;
                this._toast((err && err.body && err.body.message) || 'Could not remove task.');
            });
    }
    handleRespondToCall(event) {
        const d = (event && event.detail) || {};
        const callRequestId = d.scheduleId || d.id;
        const action = d.accept === true || d.action === 'Accept' ? 'Accept' : 'Reject';
        this._respondToCall(callRequestId, action);
    }
    handleAcceptCallRequest(event) {
        const callRequestId = event.currentTarget.dataset.id;
        this._respondToCall(callRequestId, 'Accept');
    }
    handleRejectCallRequest(event) {
        const callRequestId = event.currentTarget.dataset.id;
        this._respondToCall(callRequestId, 'Reject');
    }
    _respondToCall(callRequestId, action) {
        const previous = this.callRequests;
        // Optimistic: remove from pending list immediately.
        this.callRequests = (this.callRequests || []).filter(c => c.id !== callRequestId);
        if (!isSfIdM(callRequestId)) { this._toast(action === 'Accept' ? 'Request accepted' : 'Request rejected'); return; }
        respondToCallRequest({ callRequestId, action })
            .then(() => { this._toast(action === 'Accept' ? 'Request accepted' : 'Request rejected'); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMentorshipController.respondToCallRequest error', err);
                this.callRequests = previous;
                this._toast((err && err.body && err.body.message) || 'Could not respond.');
            });
    }
    handleAddTaskBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.showAddTask = false;
        }
    }
    handleStopProp(event) { event.stopPropagation(); }

    _toast(msg) {
        this.toastMessage = msg;
        this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2400);
    }
    disconnectedCallback() { if (this._toastTimer) clearTimeout(this._toastTimer); }
}