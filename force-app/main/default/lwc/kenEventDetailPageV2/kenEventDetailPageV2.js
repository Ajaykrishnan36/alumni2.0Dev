import { LightningElement, api, track } from 'lwc';

const TABS = [
    { id: 'about',        label: 'About' },
    { id: 'schedule',     label: 'Schedule' },
    { id: 'participants', label: 'Participants' },
    { id: 'updates',      label: 'Event Updates' }
];

export default class KenEventDetailPageV2 extends LightningElement {
    @api event = {};
    // QA Bug — true when the current user hosts this event: show Cancel/Delete, hide Register.
    @api isHostView = false;
    // Host-only: who is ALLOWED to see/register (resolved from the event's target audience).
    @api eligibleAudience = null;
    @track activeTab = 'about';

    get tabs() {
        // The Eligible Audience tab is appended ONLY for the host/admin view.
        const list = this.isHostView
            ? [...TABS, { id: 'audience', label: 'Eligible Audience' }]
            : TABS;
        return list.map(t => ({
            ...t,
            cssClass: t.id === this.activeTab ? 'tab tab--active' : 'tab'
        }));
    }
    get isAbout()        { return this.activeTab === 'about'; }
    get isSchedule()     { return this.activeTab === 'schedule'; }
    get isParticipants() { return this.activeTab === 'participants'; }
    get isUpdates()      { return this.activeTab === 'updates'; }
    // Only ever true for host view (the tab itself is host-only).
    get isAudience()     { return this.isHostView && this.activeTab === 'audience'; }

    // ----- Eligible Audience (read-only, host-only) -----
    get audienceData()        { return this.eligibleAudience || {}; }
    get audienceHasAudience() { return !!(this.eligibleAudience && this.eligibleAudience.hasAudience); }
    get audienceRules() {
        const rules = this.eligibleAudience && Array.isArray(this.eligibleAudience.ruleSummary)
            ? this.eligibleAudience.ruleSummary : [];
        return rules.map((r, i) => ({ key: `ar-${i}`, text: r }));
    }
    get hasAudienceRules()    { return this.audienceRules.length > 0; }
    get audienceMembers() {
        const m = this.eligibleAudience && Array.isArray(this.eligibleAudience.members)
            ? this.eligibleAudience.members : [];
        return m.map((row, i) => ({
            key: `am-${i}`,
            name: row.name || '—',
            email: row.email || '',
            initial: (row.name || '?').charAt(0).toUpperCase()
        }));
    }
    get hasAudienceMembers()  { return this.audienceMembers.length > 0; }
    get audienceTotalCount()  { return Number(this.audienceData.totalCount) || 0; }
    get audienceCountLabel()  { return `${this.audienceTotalCount} eligible`; }
    get audienceTruncated()   { return !!this.audienceData.truncated; }
    get audienceTruncatedLabel() { return `Showing first 200 of ${this.audienceTotalCount}`; }
    // Distinguish "open to all" from "targeted but nobody matched".
    get audienceIsOpen()      { return !this.audienceHasAudience; }
    get audienceNoMatches()   { return this.audienceHasAudience && !this.hasAudienceMembers; }

    // Time-based status for Online events (computed in the parent's mapEventDetail).
    get isHappeningNow() { return !!(this.event && this.event.isHappeningNow); }
    get showJoinNow()    { return !!(this.event && this.event.showJoinNow && this.event.meetingLink); }

    // Meeting status card (Schedule tab)
    get meetingPanelLabel() {
        return (this.event && this.event.isOnline) ? 'Online Meeting' : 'Event Timing';
    }
    get meetingTimeText() {
        const t = this.event && this.event.timeRange;
        return t && t.length ? t : 'Time to be announced';
    }
    get meetingStatusText() {
        const e = this.event || {};
        if ((e.eventStatus || '').toLowerCase() === 'cancelled') return 'Cancelled';
        return 'Scheduled';
    }
    handleJoinNow() {
        const link = this.event && this.event.meetingLink;
        if (!link) return;
        try { window.open(link, '_blank', 'noopener'); } catch (e) { window.location.assign(link); }
    }

    get heroStyle() {
        const g = this.event && this.event.heroGrad
            ? this.event.heroGrad
            : 'linear-gradient(135deg,#3061FF,#86E1FF)';
        const img = (this.event && this.event.image && typeof this.event.image === 'string')
            ? this.event.image.trim() : '';
        if (img && /^(https?:|\/|data:image)/.test(img)) {
            return `background:linear-gradient(180deg,rgba(0,0,0,0.05) 0%,rgba(0,0,0,0.55) 100%),url('${img}') center/cover, ${g}`;
        }
        return `background:${g}`;
    }

    get descriptionParagraphs() {
        return (this.event && this.event.fullDescription ? this.event.fullDescription : '')
            .split(/\n\s*\n/)
            .map(p => p.trim())
            .filter(p => p.length)
            .map((text, i) => ({ key: `p-${i}`, text }));
    }
    get hasFullDescription() { return this.descriptionParagraphs.length > 0; }
    get hasWhatToExpect()    { return !!(this.event && Array.isArray(this.event.whatToExpect) && this.event.whatToExpect.length > 0); }
    get hasSpeakers()        { return !!(this.event && Array.isArray(this.event.speakers) && this.event.speakers.length > 0); }
    get whatToExpectDecorated() {
        return (this.event && this.event.whatToExpect ? this.event.whatToExpect : []).map((w, i) => ({
            ...w,
            key: w.id || `w-${i}`
        }));
    }

    // QA Bug — render the REAL configured "What to Expect" text (falls back to the
    // synthetic icon bullets only when no real text exists).
    _toParagraphs(text, prefix) {
        return String(text || '')
            .split(/\n+/)
            .map(p => p.trim())
            .filter(p => p.length)
            .map((t, i) => ({ key: `${prefix}-${i}`, text: t }));
    }
    get whatToExpectTextParagraphs() { return this._toParagraphs(this.event && this.event.whatToExpectText, 'wte'); }
    get hasWhatToExpectText() { return this.whatToExpectTextParagraphs.length > 0; }

    // QA Bug — Agenda section (field existed but was never rendered).
    get agendaParagraphs() { return this._toParagraphs(this.event && this.event.agendaText, 'ag'); }
    get hasAgenda() { return this.agendaParagraphs.length > 0; }

    // QA Bug — Host Details + Event Information block.
    get hostName()      { return (this.event && this.event.organizer) ? this.event.organizer : ''; }
    get hostEmail()     { return (this.event && this.event.organizerEmail) ? this.event.organizerEmail : ''; }
    get eventLocation() { return (this.event && (this.event.location || this.event.loc)) ? (this.event.location || this.event.loc) : ''; }
    get hostTypeLabel() { return (this.event && (this.event.hostTypeLabel || this.event.hostType)) ? (this.event.hostTypeLabel || this.event.hostType) : ''; }
    get hasHostInfo()   { return !!(this.hostName || this.hostEmail || this.eventLocation || this.hostTypeLabel); }
    get speakersDecorated() {
        return (this.event && this.event.speakers ? this.event.speakers : []).map((s, i) => ({
            ...s,
            key: s.id || `sp-${i}`,
            initial: s.initial || (s.name || '?').charAt(0).toUpperCase(),
            avatarStyle: `background:${s.color || '#3061FF'};`
        }));
    }

    get hasSchedule()     { return !!(this.event && this.event.schedule && this.event.schedule.length); }
    get hasParticipants() { return !!(this.event && this.event.participants && this.event.participants.length); }
    get hasUpdatesList()  { return !!(this.event && this.event.updates && this.event.updates.length); }
    get hasSurvey()       { return !!(this.event && this.event.survey); }
    get hasRegistration() { return !!(this.event && this.event.registration); }

    get scheduleDecorated() {
        return (this.event && this.event.schedule ? this.event.schedule : []).map((s, i) => ({
            ...s,
            key: s.id || `s-${i}`
        }));
    }
    get participantsDecorated() {
        return (this.event && this.event.participants ? this.event.participants : []).map((p, i) => ({
            ...p,
            key: p.id || `p-${i}`,
            initial: (p.name || '?').charAt(0).toUpperCase()
        }));
    }
    get updatesDecorated() {
        return (this.event && this.event.updates ? this.event.updates : []).map((u, i) => ({
            ...u,
            key: u.id || `u-${i}`
        }));
    }
    get participantsCount() {
        const g = this.event && this.event.going;
        const n = Number(g);
        if (g !== undefined && g !== null && !isNaN(n)) return n;
        return this.participantsDecorated.length;
    }
    get displayCategory() { return (this.event && this.event.category) ? this.event.category : 'Event'; }
    get displayPrice()    { return (this.event && this.event.price) ? this.event.price : 'Free'; }
    get displayTitle()    { return (this.event && this.event.title) ? this.event.title : ''; }
    get organizerLine() {
        const desc = (this.event && this.event.desc) ? this.event.desc : '';
        const org  = (this.event && this.event.organizer) ? this.event.organizer : '';
        return org ? `${desc} Hosted by ${org}, this event brings together alumni for a memorable shared experience.` : desc;
    }

    // Hide attendee "Register Now" for the host's own event; show it otherwise.
    get showRegister() { return !this.isHostView; }

    // QA Bug — a completed (or cancelled/past) event can no longer be registered for.
    get isEventClosed() {
        const e = this.event || {};
        const st = (e.eventStatus || '').toLowerCase();
        if (st === 'completed' || st === 'cancelled' || st === 'closed') return true;
        // Past by end date (the board passes endDateRaw; detail may pass endDate).
        const endRaw = e.endDateRaw || e.endDate;
        if (endRaw) {
            const end = new Date(endRaw);
            if (!isNaN(end.getTime())) {
                const today = new Date(); today.setHours(0, 0, 0, 0);
                if (end.getTime() < today.getTime()) return true;
            }
        }
        return false;
    }
    get registerDisabled() { return this.isEventClosed; }
    get registerLabel() { return this.isEventClosed ? 'Registration Closed' : 'Register Now'; }

    // QA Bug — a completed/past event must read as "Completed", not offer Register.
    // Completed = explicit status OR past end date (but NOT cancelled).
    get isCancelledEvent() { return ((this.event && this.event.eventStatus) || '').toLowerCase() === 'cancelled'; }
    get isCompletedEvent() {
        if (this.isCancelledEvent) return false;
        const st = ((this.event && this.event.eventStatus) || '').toLowerCase();
        if (st === 'completed' || st === 'closed') return true;
        const endRaw = (this.event && (this.event.endDateRaw || this.event.endDate)) || null;
        if (endRaw) {
            const end = new Date(endRaw);
            if (!isNaN(end.getTime())) {
                const today = new Date(); today.setHours(0, 0, 0, 0);
                return end.getTime() < today.getTime();
            }
        }
        return false;
    }
    // Show the Register button only to a non-host on an event that is still open.
    get showRegisterButton() { return !this.isHostView && !this.isEventClosed; }
    // Status pill (hero + footer) for closed events.
    get showStatusPill() { return this.isCompletedEvent || this.isCancelledEvent; }
    get statusPillLabel() { return this.isCancelledEvent ? 'Cancelled' : 'Completed'; }
    get statusPillClass() { return this.isCancelledEvent ? 'ev-status-pill ev-status-pill--cancelled' : 'ev-status-pill ev-status-pill--completed'; }
    // Completed attendees can leave feedback instead of registering.
    get showFeedbackButton() { return !this.isHostView && this.isCompletedEvent; }
    handleFeedback() { this.dispatchEvent(new CustomEvent('submitfeedback', { detail: { id: this.event ? this.event.id : null } })); }

    // Meals for Attendees — server parses Meals_JSON__c into [{dateLabel, items}].
    get meals() {
        const rows = (this.event && Array.isArray(this.event.meals)) ? this.event.meals : [];
        return rows.map((m, i) => ({
            key: m.key || `meal-${i}`,
            line: (m.dateLabel && m.items) ? `${m.dateLabel} (${m.items})` : (m.dateLabel || m.items || '')
        })).filter(m => m.line);
    }
    get hasMeals() { return this.meals.length > 0; }

    handleTab(e)  { this.activeTab = e.currentTarget.dataset.id; }
    handleBack()  { this.dispatchEvent(new CustomEvent('back')); }
    handleRegister() { this.dispatchEvent(new CustomEvent('rsvp', { detail: { id: this.event ? this.event.id : null } })); }
    // QA Bug — host actions surfaced in the detail footer.
    handleCancel() { this.dispatchEvent(new CustomEvent('cancelevent', { detail: { id: this.event ? this.event.id : null } })); }
    handleDelete() { this.dispatchEvent(new CustomEvent('deleteevent', { detail: { id: this.event ? this.event.id : null } })); }
    handleViewRegistration() {
        this.dispatchEvent(new CustomEvent('viewregistration', { detail: { id: this.event ? this.event.id : null } }));
    }
    handleViewQuestionnaire() {
        this.dispatchEvent(new CustomEvent('viewquestionnaire', { detail: { id: this.event ? this.event.id : null } }));
    }
}