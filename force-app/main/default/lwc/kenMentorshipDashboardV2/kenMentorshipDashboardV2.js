// Single-call mentorship dashboard orchestrator.
// Hits KenMentorshipController.getMentorshipDashboardData() exactly once on mount,
// then distributes slices to the three child rails. Mutations (add task, schedule)
// reuse the existing per-resource Apex methods and refresh via a single re-fetch.
import { LightningElement, track } from 'lwc';
import getMentorshipDashboardData from '@salesforce/apex/KenMentorshipController.getMentorshipDashboardData';
import saveTaskForCurrentMentee from '@salesforce/apex/KenMentorshipController.saveTaskForCurrentMentee';
import scheduleCallForCurrentMentee from '@salesforce/apex/KenMentorshipController.scheduleCallForCurrentMentee';
import searchMentors from '@salesforce/apex/KenMentorshipController.searchMentors';

const EXPERTISE_OPTIONS = [
    { label: 'Any expertise', value: '' },
    { label: 'Project Management', value: 'Project Management' },
    { label: 'Design', value: 'Design' },
    { label: 'Development', value: 'Development' }
];

// QA Bug #120 — sort options for the matchmaking list.
const SORT_OPTIONS = [
    { label: 'Best match',      value: '' },
    { label: 'Name (A→Z)',      value: 'nameAsc' },
    { label: 'Name (Z→A)',      value: 'nameDesc' },
    { label: 'Most capacity',   value: 'capacityDesc' }
];

const EMPTY_DATA = {
    connections: [],
    sessions: [],
    tasks: [],
    currentUserIsMentor: false,
    currentMonthLabel: ''
};

export default class KenMentorshipDashboardV2 extends LightningElement {
    @track data = EMPTY_DATA;
    @track isLoading = true;
    @track loadError = null;

    // Add-task modal state
    @track showAddTask = false;
    @track newTaskTitle = '';
    @track newTaskDesc = '';
    @track newTaskPriority = 'Medium';

    // Schedule modal state — defer to existing kenScheduleCallWizardV2.
    @track showScheduleCall = false;
    @track selectedMentor = null;

    // Toast
    @track toastVisible = false;
    @track toastMessage = '';
    _toastTimer = null;

    // Epic 1 — matchmaking filters + results
    @track fCompany = '';
    @track fIndustry = '';
    @track fLocation = '';
    @track fExpertise = '';
    // QA Bug #120 — free-text keyword search + sort dropdown
    @track fKeyword = '';
    @track fSort = '';
    @track mentors = [];
    @track searching = false;
    @track searched = false;

    // Epic 2 — preferences overlay (replaces the dead /my-profile?section=mentor link)
    @track showPreferences = false;

    connectedCallback() {
        this.loadDashboard();
    }

    disconnectedCallback() {
        if (this._toastTimer) clearTimeout(this._toastTimer);
    }

    loadDashboard() {
        this.isLoading = true;
        getMentorshipDashboardData()
            .then(res => {
                this.data = res || EMPTY_DATA;
                this.loadError = null;
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMentorshipController.getMentorshipDashboardData error', err);
                this.loadError = err;
                this.data = EMPTY_DATA;
            })
            .finally(() => { this.isLoading = false; });
    }

    get showBecomeMentorCta() {
        // Show unless the user is explicitly already a mentor. Guarding on `=== false`
        // hid the CTA entirely when the DTO returned null/undefined.
        return this.data && this.data.currentUserIsMentor !== true;
    }

    // ----- Epic 1: Matchmaking filters -----
    get expertiseOptions() { return EXPERTISE_OPTIONS; }
    get sortOptions() { return SORT_OPTIONS; }
    get hasResults() { return this.mentors && this.mentors.length > 0; }
    get noResults() { return this.searched && !this.searching && this.mentors.length === 0; }

    handleFCompany(e) { this.fCompany = e.target.value; }
    handleFIndustry(e) { this.fIndustry = e.target.value; }
    handleFLocation(e) { this.fLocation = e.target.value; }
    handleFExpertise(e) { this.fExpertise = e.target.value; }
    // QA Bug #120 — keyword + sort handlers. Sort re-orders the current result set
    // client-side so the user gets instant feedback without re-hitting Apex.
    handleFKeyword(e) { this.fKeyword = e.target.value; }
    handleFSort(e) {
        this.fSort = e.target.value;
        if (this.mentors && this.mentors.length) {
            this.mentors = this._sort(this.mentors.slice());
        }
    }

    handleSearchMentors() {
        this.searching = true;
        this.searched = true;
        // Expertise is the server-side filter; Company/Industry/Location/Keyword narrow client-side
        // against the returned card text (the matchmaking DTO doesn't carry those fields yet).
        searchMentors({ expertise: this.fExpertise || '', communication: '' })
            .then(rows => {
                const narrowed = this._narrow(rows || []).map(m => this._decorateMentor(m));
                this.mentors = this._sort(narrowed);
                this.searching = false;
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMentorshipController.searchMentors error', err);
                this.mentors = [];
                this.searching = false;
                this._toast((err && err.body && err.body.message) || 'Could not search mentors');
            });
    }

    handleClearFilters() {
        this.fCompany = ''; this.fIndustry = ''; this.fLocation = ''; this.fExpertise = '';
        this.fKeyword = ''; this.fSort = '';
        this.mentors = []; this.searched = false;
    }

    _narrow(rows) {
        const terms = [this.fCompany, this.fIndustry, this.fLocation, this.fKeyword]
            .map(t => (t || '').trim().toLowerCase()).filter(t => t);
        if (!terms.length) return rows;
        return rows.filter(m => {
            const hay = [m.name, m.expertise, m.menteeTypes, m.communication]
                .map(x => (x || '').toLowerCase()).join(' ');
            return terms.every(t => hay.indexOf(t) > -1);
        });
    }

    // QA Bug #120 — client-side sort. '' (Best match) leaves server order untouched.
    _sort(rows) {
        const s = this.fSort;
        if (!s) return rows;
        const out = rows.slice();
        if (s === 'nameAsc')      out.sort((a, b) => (a.name || '').localeCompare(b.name || ''));
        else if (s === 'nameDesc') out.sort((a, b) => (b.name || '').localeCompare(a.name || ''));
        else if (s === 'capacityDesc') {
            out.sort((a, b) => {
                const ca = a.unlimited ? 9999 : (a.capacity || 0);
                const cb = b.unlimited ? 9999 : (b.capacity || 0);
                return cb - ca;
            });
        }
        return out;
    }

    _decorateMentor(m) {
        return {
            ...m,
            avatar: (m.name || 'M').trim().charAt(0).toUpperCase(),
            capacityLabel: m.unlimited ? 'Unlimited capacity'
                : (m.capacity != null ? m.capacity + ' mentees' : 'Open'),
            expertiseLabel: (m.expertise || '').split(';').join(', ') || '—',
            commLabel: (m.communication || '').split(';').join(', ') || '—'
        };
    }

    handleConnectMentor(event) {
        const name = event.currentTarget.dataset.name || 'mentor';
        this._toast('Connect request flow opens from the Network tab for ' + name);
    }

    // ----- Connections handlers -----
    handleConnectionClick(event) {
        const d = (event && event.detail) || {};
        // Clicking an accepted connection opens the schedule wizard pre-targeted at
        // that mentor, so the confirm path carries a real mentorId to Apex.
        const idRaw = d.id || null;
        const id = typeof idRaw === 'string' && /^[a-zA-Z0-9]{15,18}$/.test(idRaw) ? idRaw : null;
        if (id) {
            this.selectedMentor = { id, name: d.name || 'Mentor' };
            this.showScheduleCall = true;
        } else {
            this._toast(`Opening ${d.name || 'profile'}…`);
        }
    }
    handleConnSearch() {
        // Search is local in the child; nothing to do here right now.
    }

    // ----- Calendar handlers -----
    handleScheduleCall() {
        this.selectedMentor = null;
        this.showScheduleCall = true;
    }
    handleCloseSchedule() {
        this.showScheduleCall = false;
        this.selectedMentor = null;
    }
    handleScheduleConfirm(event) {
        const d = (event && event.detail) || {};
        const mentorIdRaw = (this.selectedMentor && this.selectedMentor.id) || d.mentorId || null;
        const mentorId = typeof mentorIdRaw === 'string' && /^[a-zA-Z0-9]{15,18}$/.test(mentorIdRaw) ? mentorIdRaw : null;
        const request = {
            mentorId,
            selectedMentor: mentorId,
            mentorValue: mentorId,
            participantType: 'mentor',
            title: d.topic || d.title || 'Mentorship Session',
            meetingDate: d.meetingDate || d.date || '',
            startTime: d.startTime || '',
            endTime: d.endTime || '',
            description: d.agenda || d.description || '',
            meetingType: d.meetingType || 'Online'
        };
        this.showScheduleCall = false;
        // Always call Apex — when mentorId is null it resolves the single accepted
        // mentor server-side (or returns a clear validation message).
        scheduleCallForCurrentMentee({ request })
            .then(() => {
                this._toast('Booking request sent');
                this.loadDashboard();
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMentorshipController.scheduleCallForCurrentMentee error', err);
                this._toast((err && err.body && err.body.message) || 'Could not send booking request');
            });
    }
    handleLeaveFeedback() {
        this._toast('Feedback flow coming soon');
    }

    // ----- Tasks handlers -----
    handleAddTask() {
        this.newTaskTitle = '';
        this.newTaskDesc = '';
        this.newTaskPriority = 'Medium';
        this.showAddTask = true;
    }
    handleTaskClick() {
        // Future: open task detail.
    }
    handleAddTaskClose() { this.showAddTask = false; }
    handleAddTaskBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('dash-modal-backdrop')) {
            this.showAddTask = false;
        }
    }
    handleStopProp(event) { event.stopPropagation(); }
    handleTaskTitle(event) { this.newTaskTitle = event.target.value; }
    handleTaskDesc(event) { this.newTaskDesc = event.target.value; }
    handleTaskPriority(event) { this.newTaskPriority = event.target.value; }
    handleAddTaskSubmit() {
        const title = (this.newTaskTitle || '').trim();
        if (!title) return;
        const request = {
            title,
            description: this.newTaskDesc || '',
            descriptionHtml: this.newTaskDesc || '',
            priority: this.newTaskPriority || 'Medium',
            status: 'In Progress'
        };
        this.showAddTask = false;
        saveTaskForCurrentMentee({ request })
            .then(() => {
                this._toast('Task added');
                this.loadDashboard();
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenMentorshipController.saveTaskForCurrentMentee error', err);
                this._toast((err && err.body && err.body.message) || 'Could not add task');
            });
    }

    // ----- Become Mentor / Edit Preference -> open the preferences editor overlay -----
    // (Replaces the old dead /my-profile?section=mentor link that 404'd.)
    handleBecomeMentor() { this.showPreferences = true; }
    handleEditPreference() { this.showPreferences = true; }
    handlePreferencesClose() {
        this.showPreferences = false;
        // Re-fetch so the dashboard reflects any willing-to-mentor / preference changes.
        this.loadDashboard();
    }

    _toast(msg) {
        this.toastMessage = msg;
        this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2400);
    }
}