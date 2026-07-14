// V2 wiring — calls OLD KenPortalEventController. Do not modify the OLD controller.
// Imperative calls (not @wire) for consistency: getAllEvents is cacheable, getEventDetails too,
// but we want one pattern here. Mock event data below stays as fallback (rich detail fields
// like schedule/speakers/registration aren't returned by OLD list method).
import { LightningElement, track } from 'lwc';
import basePath from '@salesforce/community/basePath';
import getAllEvents from '@salesforce/apex/KenPortalEventController.getAllEvents';
import getMyEvents from '@salesforce/apex/KenPortalEventController.getMyEvents';
import getPastEvents from '@salesforce/apex/KenPortalEventController.getPastEvents';
import getHostedEventsForCurrentUser from '@salesforce/apex/KenPortalEventController.getHostedEventsForCurrentUser';
import getEventDetails from '@salesforce/apex/KenPortalEventController.getEventDetails';
import getEventSessions from '@salesforce/apex/KenPortalEventController.getEventSessions';
import getEventDetailDecorations from '@salesforce/apex/KenPortalEventController.getEventDetailDecorations';
import getEventEligibleAudience from '@salesforce/apex/KenPortalEventController.getEventEligibleAudience';
import saveRegistrations from '@salesforce/apex/KenPortalEventController.saveRegistrations';
import cancelRegistrations from '@salesforce/apex/KenPortalEventController.cancelRegistrations';
import getAlumniRolesForPerson from '@salesforce/apex/KenAlumniOnboardingService.getAlumniRolesForPerson';
import createEventApex from '@salesforce/apex/KenPortalEventController.createEvent';
import saveEventDraftApex from '@salesforce/apex/KenPortalEventController.saveEventDraft';
import createEventSegmentation from '@salesforce/apex/KenPortalEventController.createEventSegmentation';
import saveSegmentation from '@salesforce/apex/KenAudienceEngineService.saveSegmentation';
import cancelEventApex from '@salesforce/apex/KenPortalEventController.cancelEvent';
import deleteEventApex from '@salesforce/apex/KenPortalEventController.deleteEvent';

const SF_ID_RE = /^[a-zA-Z0-9]{15,18}$/;
const isSfId = (v) => typeof v === 'string' && SF_ID_RE.test(v);

// Shared formatDate helper — "2026-07-15" -> "15 Jul 2026"; with time -> "15 Jul 2026, 04:00 PM"
const formatDate = (iso, withTime = false) => {
    if (!iso) return '';
    const d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    const opts = { day: '2-digit', month: 'short', year: 'numeric' };
    if (withTime) { opts.hour = '2-digit'; opts.minute = '2-digit'; opts.hour12 = true; }
    return d.toLocaleDateString('en-IN', opts);
};

const MOCK_EVENTS = []; // Mock events removed — real data from KenPortalEventController.

// Side-rail mini list — derived empty for now; rail still renders the hosted list from Apex.
const REGISTERED_MINI = [];

export default class KenAllEventsFullPageV2 extends LightningElement {
    // 'board' replaces 'landing'; 'detail' is the inline detail page;
    // 'registration' and 'questionnaire' are the two new inline sub-views.
    // 'rsvp' and 'host' remain — they are full-screen wizard modals.
    @track view = 'board';
    @track activeTab = 'upcoming';
    @track activeCategory = 'All';
    @track searchTerm = ''; // QA Bug #129 — free-text search
    @track selectedEventId = null;
    @track toastMsg = '';
    @track toastVisible = false;

    // Live data — starts empty + loading so no mock flash; mock only on Apex error.
    @track events = [];
    @track myEvents = [];
    @track pastEvents = [];
    @track hostedEvents = [];
    @track selectedEventDetail = null;
    // Host-only: who is ALLOWED to see/register (resolved from the event's target audience).
    @track selectedEligibleAudience = null;
    @track eventsError = null;
    @track isLoading = true;
    @track isLoadingMine = true;
    @track isLoadingPast = true;
    @track isLoadingHosted = true;
    @track constituentRoleId = null;

    connectedCallback() {
        // Restore tab/view/id from URL so refresh keeps the user in place.
        try {
            const params = new URLSearchParams(window.location.search);
            const tab = params.get('tab');
            const view = params.get('view');
            const id = params.get('id');
            const VALID_TABS = ['upcoming', 'myevents', 'past', 'hosted'];
            const VALID_VIEWS = ['board', 'detail', 'registration', 'questionnaire', 'rsvp', 'host'];
            if (tab && VALID_TABS.indexOf(tab) > -1) this.activeTab = tab;
            if (view && VALID_VIEWS.indexOf(view) > -1) this.view = view;
            if (id) this.selectedEventId = id;
        } catch (e) { /* ignore */ }
        this.loadEvents();
        this.loadMyEvents();
        this.loadPastEvents();
        this.loadHostedEvents();
        // Resolve constituentRoleId for save/cancel registrations.
        getAlumniRolesForPerson({ personId: null })
            .then(roles => {
                const role = Array.isArray(roles) && roles.length ? roles[0] : null;
                this.constituentRoleId = (role && role.constituentRoleId) || null;
            })
            .catch(() => { /* non-fatal — write paths gracefully no-op */ });
    }

    syncUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            if (this.activeTab) params.set('tab', this.activeTab); else params.delete('tab');
            if (this.view && this.view !== 'board') params.set('view', this.view); else params.delete('view');
            if (this.selectedEventId) params.set('id', String(this.selectedEventId)); else params.delete('id');
            const qs = params.toString();
            const newUrl = window.location.pathname + (qs ? '?' + qs : '');
            window.history.replaceState(null, '', newUrl);
        } catch (e) { /* ignore */ }
    }

    loadEvents() {
        this.isLoading = true;
        getAllEvents()
            .then(rows => {
                this.events = Array.isArray(rows) ? this.mapEventList(rows) : [];
                this.eventsError = null;
                this.isLoading = false;
            })
            .catch(err => {
                // Apex failed — empty state, no mock flash.
                this.eventsError = err;
                this.events = [];
                this.isLoading = false;
                // eslint-disable-next-line no-console
                console.error('KenPortalEventController.getAllEvents error', err);
            });
    }

    loadMyEvents() {
        this.isLoadingMine = true;
        getMyEvents()
            .then(rows => {
                this.myEvents = Array.isArray(rows) ? this.mapEventList(rows) : [];
                this.isLoadingMine = false;
            })
            .catch(err => {
                this.myEvents = [];
                this.isLoadingMine = false;
                // eslint-disable-next-line no-console
                console.error('KenPortalEventController.getMyEvents error', err);
            });
    }

    loadPastEvents() {
        this.isLoadingPast = true;
        getPastEvents()
            .then(rows => {
                this.pastEvents = Array.isArray(rows) ? this.mapEventList(rows) : [];
                this.isLoadingPast = false;
            })
            .catch(err => {
                this.pastEvents = [];
                this.isLoadingPast = false;
                // eslint-disable-next-line no-console
                console.error('KenPortalEventController.getPastEvents error', err);
            });
    }

    loadHostedEvents() {
        this.isLoadingHosted = true;
        getHostedEventsForCurrentUser()
            .then(rows => {
                this.hostedEvents = Array.isArray(rows) ? this.mapEventList(rows) : [];
                this.isLoadingHosted = false;
            })
            .catch(err => {
                this.hostedEvents = [];
                this.isLoadingHosted = false;
                // eslint-disable-next-line no-console
                console.error('KenPortalEventController.getHostedEventsForCurrentUser error', err);
            });
    }

    get hasEvents() { return (this.events || []).length > 0; }
    get showEmptyState() { return !this.isLoading && !this.hasEvents && !this.eventsError; }

    // OLD EventWrapper → existing event card shape used by the template.
    mapEventList(rows) {
        const grads = [
            'linear-gradient(135deg,#0B1438 0%,#3061FF 60%,#86E1FF 100%)',
            'linear-gradient(135deg,#B033C8 0%,#E8B4D6 100%)',
            'linear-gradient(135deg,#19A974 0%,#67A1C8 100%)',
            'linear-gradient(135deg,#F59E0B 0%,#FCD34D 100%)',
            'linear-gradient(135deg,#3061FF 0%,#86E1FF 100%)',
            'linear-gradient(135deg,#19A974 0%,#A6E3B7 100%)'
        ];
        return rows.map((r, i) => {
            const startDate = r.startDate ? new Date(r.startDate) : null;
            const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
            const month = startDate && !isNaN(startDate.getTime()) ? months[startDate.getMonth()] : '';
            const day = startDate && !isNaN(startDate.getTime()) ? String(startDate.getDate()) : '';
            const dateStr = formatDate(r.startDate);
            return {
                id: r.id,
                title: r.title || '',
                desc: r.description || '',
                date: dateStr,
                time: r.startTime || '',
                loc: r.location || '',
                category: r.categories || r.eventType || 'Event',
                price: this._priceLabel(r.fee),
                going: Number(r.participantsCount) || 0,
                organizer: r.organizer || '',
                organizerEmail: r.organizerEmail || '',
                month,
                day,
                heroGrad: grads[i % grads.length],
                image: r.imageUrl || '',
                eventStatus: r.eventStatus || '',
                endDateRaw: r.endDate || null,
                // live status (reuses the same time-window logic as the detail view)
                meetingLink: r.meetingLink || '',
                isHappeningNow: this._isHappeningNow(r),
                showJoinNow: (r.hostType || '') === 'Online' && this._isHappeningNow(r) && !!r.meetingLink,
                // Host/event information line for the Hosted list
                hostInfo: this._hostInfoLine(r)
            };
        });
    }

    _hostInfoLine(r) {
        const bits = [];
        // Surface the approval status so the host can tell a Pending/Rejected event
        // apart from a live Approved one (QA Bug — pending events looked "live").
        if (r.eventStatus) bits.push(r.eventStatus);
        if (r.organizer) bits.push(`Hosted by ${r.organizer}`);
        if (r.postedDate) bits.push(`Submitted ${formatDate(r.postedDate)}`);
        if (r.participantsCount != null && r.participantsCount !== '') bits.push(`Capacity ${r.participantsCount}`);
        bits.push(this._priceLabel(r.fee));
        if (r.location) bits.push(r.location);
        return bits.join(' · ');
    }

    // QA Bug — paid events were always shown as "Free". Render the real fee.
    _priceLabel(fee) {
        const n = Number(fee);
        return (fee != null && !isNaN(n) && n > 0) ? `₹${n}` : 'Free';
    }

    // ===== Hosted "View All" categorisation: Upcoming / Cancelled / Completed =====
    _hostedByBucket(bucket) {
        const today = new Date(); today.setHours(0, 0, 0, 0);
        return (this.hostedEvents || []).filter(e => {
            const status = (e.eventStatus || '').toLowerCase();
            const cancelled = status === 'cancelled';
            if (bucket === 'cancelled') return cancelled;
            if (cancelled) return false;
            const end = e.endDateRaw ? new Date(e.endDateRaw) : null;
            const isPast = end && !isNaN(end.getTime()) && end.getTime() < today.getTime();
            // Completed = an event that actually ran (Approved/Completed) and whose end
            // date has passed. A Pending/Rejected event that expired is NOT "Completed";
            // it stays in Upcoming so the host can see its unresolved status.
            const ranLive = status === 'approved' || status === 'completed';
            if (bucket === 'completed') return isPast && ranLive;
            // 'upcoming' = everything else (future, or past-but-never-approved).
            return !(isPast && ranLive);
        });
    }
    get hostedUpcoming()  { return this._hostedByBucket('upcoming'); }
    get hostedCancelled() { return this._hostedByBucket('cancelled'); }
    get hostedCompleted() { return this._hostedByBucket('completed'); }
    get hasHostedUpcoming()  { return this.hostedUpcoming.length > 0; }
    get hasHostedCancelled() { return this.hostedCancelled.length > 0; }
    get hasHostedCompleted() { return this.hostedCompleted.length > 0; }

    // ===== Host actions: Cancel / Delete / View Details =====
    // Resolve the event id from either a card button (currentTarget.dataset.id) or a
    // child-component CustomEvent (detail.id) — both the Hosted cards AND the detail
    // page now fire these.
    _eventIdFrom(event) {
        if (event && event.detail && event.detail.id) return event.detail.id;
        if (event && event.currentTarget && event.currentTarget.dataset) return event.currentTarget.dataset.id;
        return null;
    }
    handleViewDetailsEvent(event) {
        const id = this._eventIdFrom(event);
        if (id) this.handleEventClick({ detail: { id } });
    }
    handleCancelEvent(event) {
        const id = this._eventIdFrom(event);
        if (!id) return;
        // eslint-disable-next-line no-alert
        if (typeof window !== 'undefined' && window.confirm
            && !window.confirm('Cancel this event? Attendees will no longer see it.')) return;
        cancelEventApex({ eventId: id })
            .then(() => {
                this.showToast('Event cancelled');
                this.loadHostedEvents();
                this.loadEvents();
                if (this.view === 'detail') this.handleBackToBoard();
            })
            .catch(err => this.showToast((err && err.body && err.body.message) || 'Could not cancel the event.'));
    }
    handleDeleteEvent(event) {
        const id = this._eventIdFrom(event);
        if (!id) return;
        // eslint-disable-next-line no-alert
        if (typeof window !== 'undefined' && window.confirm
            && !window.confirm('Permanently delete this event? This cannot be undone.')) return;
        deleteEventApex({ eventId: id })
            .then(() => {
                this.showToast('Event deleted');
                this.loadHostedEvents();
                this.loadEvents();
                if (this.view === 'detail') this.handleBackToBoard();
            })
            .catch(err => this.showToast((err && err.body && err.body.message) || 'Could not delete the event.'));
    }

    // True when the event currently open in the detail view is one the user hosts —
    // drives the host-only Cancel/Delete actions in the detail footer.
    get isSelectedEventHosted() {
        if (!this.selectedEventId) return false;
        return (this.hostedEvents || []).some(e => e.id === this.selectedEventId);
    }

    mapEventDetail(d) {
        if (!d) return null;
        const startDate = d.startDate ? new Date(d.startDate) : null;
        const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
        const month = startDate && !isNaN(startDate.getTime()) ? months[startDate.getMonth()] : '';
        const day = startDate && !isNaN(startDate.getTime()) ? String(startDate.getDate()) : '';
        const dateStr = formatDate(d.startDate);
        return {
            id: d.id,
            title: d.title || '',
            desc: d.description || '',
            fullDescription: d.description || '',
            date: dateStr,
            month,
            day,
            category: d.categories || d.eventType || 'Event',
            image: d.image || '',
            going: Number(d.participantsCount) || 0,
            brochureUrl: d.brochureUrl || '',
            hasBrochure: d.hasBrochure === true,
            eventStatus: d.eventStatus || '',
            endDateRaw: d.endDate || null,
            // Meals for Attendees (parsed server-side from Meals_JSON__c).
            meals: Array.isArray(d.meals) ? d.meals : [],
            mealsIncluded: d.mealsIncluded === true,
            // QA Bug — paid events were "Free" in the detail hero.
            price: this._priceLabel(d.fee),
            fee: d.fee != null ? d.fee : null,
            // QA Bug — real configured "What to Expect" + "Agenda" text (not synthetic bullets).
            whatToExpectText: d.expectations || '',
            agendaText: d.agenda || '',
            speakerDetails: d.speakerDetails || '',
            // QA Bug — host details for the detail view.
            organizer: d.organizer || '',
            organizerEmail: d.organizerEmail || '',
            location: d.location || '',
            hostTypeLabel: d.hostType || '',
            // ----- time-based status for Online events -----
            hostType: d.hostType || '',
            isOnline: (d.hostType || '') === 'Online',
            meetingLink: d.meetingLink || '',
            timeRange: this._fmtTimeRange(d.startTime, d.endTime),
            isHappeningNow: this._isHappeningNow(d),
            showJoinNow: (d.hostType || '') === 'Online' && this._isHappeningNow(d) && !!d.meetingLink,
            statusTag: ((d.eventStatus || '').toLowerCase() === 'cancelled')
                ? 'Cancelled' : (this._isHappeningNow(d) ? 'Happening Now' : '')
        };
    }

    // ----- time helpers (Apex Time serialises as ms-since-midnight OR "HH:mm:ss") -----
    _timeParts(timeVal) {
        if (timeVal == null) return null;
        if (typeof timeVal === 'number') {
            const mins = Math.floor(timeVal / 60000);
            return { h: Math.floor(mins / 60), m: mins % 60 };
        }
        const m = String(timeVal).match(/(\d{1,2}):(\d{2})/);
        return m ? { h: Number(m[1]), m: Number(m[2]) } : null;
    }
    _combine(dateVal, timeVal) {
        if (!dateVal) return null;
        const base = new Date(dateVal);
        if (isNaN(base.getTime())) return null;
        const local = new Date(base.getFullYear(), base.getMonth(), base.getDate());
        const tp = this._timeParts(timeVal);
        if (tp) local.setHours(tp.h, tp.m, 0, 0);
        else local.setHours(23, 59, 0, 0); // no time → treat as end-of-day boundary
        return local;
    }
    _fmtTime(timeVal) {
        const tp = this._timeParts(timeVal);
        if (!tp) return '';
        const ampm = tp.h >= 12 ? 'PM' : 'AM';
        let h = tp.h % 12; if (h === 0) h = 12;
        return `${h}:${String(tp.m).padStart(2, '0')} ${ampm}`;
    }
    _fmtTimeRange(startVal, endVal) {
        const s = this._fmtTime(startVal);
        const e = this._fmtTime(endVal);
        if (s && e) return `${s} – ${e}`;
        return s || e || '';
    }
    _isHappeningNow(d) {
        if (!d || (d.eventStatus || '').toLowerCase() === 'cancelled') return false;
        const now = new Date();
        const startDT = this._combine(d.startDate, d.startTime);
        const endDT = this._combine(d.endDate || d.startDate, d.endTime);
        return !!(startDT && endDT && now >= startDT && now <= endDT);
    }

    // Merge the Schedule/Participants/Updates/Speakers/WhatToExpect decorations from Apex
    // into the selectedEventDetail object so the detail SPA renders rich content.
    mapEventDecorations(dec) {
        if (!dec) return {};
        const safe = (arr) => Array.isArray(arr) ? arr : [];
        return {
            schedule: safe(dec.schedule).map((s) => ({
                id: s.id,
                title: s.title || '',
                desc: s.descText || '',
                time: s.timeText || ''
            })),
            participants: safe(dec.participants).map((p) => ({
                id: p.id,
                name: p.name || 'Alumni',
                type: p.type || 'Registered'
            })),
            speakers: safe(dec.speakers).map((s, i) => ({
                id: s.id,
                name: s.name || '',
                role: s.role || '',
                image: s.image || '',
                color: ['#3061FF','#B033C8','#19A974','#F59E0B','#86E1FF','#E8B4D6'][i % 6]
            })),
            whatToExpect: safe(dec.whatToExpect).map((w, i) => ({
                id: `w-${i}`,
                icon: w.icon || '✨',
                title: w.title || '',
                desc: w.descText || ''
            })),
            updates: safe(dec.updates).map((u, i) => ({
                id: `u-${i}`,
                title: u.title || '',
                text: u.bodyText || '',
                time: u.timeText || ''
            })),
            going: Number(dec.goingCount) || 0
        };
    }

    get viewState() {
        return {
            isMainBoard:           this.view === 'board',
            isEventDetail:         this.view === 'detail',
            isRegistrationSummary: this.view === 'registration',
            isQuestionnaire:       this.view === 'questionnaire',
            isRsvp:                this.view === 'rsvp',
            isHost:                this.view === 'host'
        };
    }
    get showRail() { return this.view === 'board'; }

    get isTabAll()  { return this.activeTab === 'upcoming'; }
    get isTabMine() { return this.activeTab === 'myevents'; }
    get isTabPast() { return this.activeTab === 'past'; }
    get isTabHosted() { return this.activeTab === 'hosted'; }

    // QA Bug #129 — free-text search across event title / category / venue / host.
    // Distinct categories present in the live data — drives the filter chips so the
    // chip set always reflects the REAL Event_Type__c values (e.g. Conference, Seminar,
    // Exhibitions, Startups, Virtual Submits) instead of a hardcoded label list.
    get categoryOptions() {
        const seen = new Map(); // lower -> original casing (first seen)
        (this.events || []).forEach(e => {
            const c = (e.category || '').trim();
            if (!c) return;
            const key = c.toLowerCase();
            if (!seen.has(key)) seen.set(key, c);
        });
        return Array.from(seen.values()).sort((a, b) => a.localeCompare(b));
    }

    // Case-insensitive, tolerant category match: equal OR either string contains the
    // other (so a chip "Workshop" matches "Workshops"/"Career Workshop", etc.).
    _categoryMatches(eventCat, chip) {
        const a = (eventCat || '').trim().toLowerCase();
        const b = (chip || '').trim().toLowerCase();
        if (!b || b === 'all') return true;
        if (!a) return false;
        return a === b || a.indexOf(b) > -1 || b.indexOf(a) > -1;
    }

    get filteredEvents() {
        let all = this.events || [];
        if (this.activeCategory && this.activeCategory !== 'All') {
            all = all.filter(e => this._categoryMatches(e.category, this.activeCategory));
        }
        const term = (this.searchTerm || '').trim().toLowerCase();
        if (!term) return all;
        return all.filter(e => {
            const hay = [e.title, e.category, e.venue, e.location, e.host, e.description]
                .map(x => (x == null ? '' : String(x)).toLowerCase()).join(' ');
            return hay.indexOf(term) > -1;
        });
    }
    handleEventsSearch(event) {
        this.searchTerm = (event && event.target && event.target.value) || '';
    }
    get featuredEvents() { return this.filteredEvents.slice(0, 3); }
    get upcomingEvents() { return this.filteredEvents.slice(3); }
    get featuredCount()  { return this.featuredEvents.length; }
    get upcomingCount()  { return this.upcomingEvents.length; }
    get myCount()        { return (this.myEvents || []).length; }
    get pastCount()      { return (this.pastEvents || []).length; }
    get hostedCount()    { return (this.hostedEvents || []).length; }

    get registeredMini() { return REGISTERED_MINI; }

    // Empty-state flags — distinguish loading from empty so the UI never flashes empty.
    get showMyEmpty()     { return !this.isLoadingMine && this.myCount === 0; }
    get showPastEmpty()   { return !this.isLoadingPast && this.pastCount === 0; }
    get showHostedEmpty() { return !this.isLoadingHosted && this.hostedCount === 0; }

    get selectedEvent() {
        const base = (this.events || []).find(e => e.id === this.selectedEventId)
            || (this.myEvents || []).find(e => e.id === this.selectedEventId)
            || (this.pastEvents || []).find(e => e.id === this.selectedEventId)
            || (this.hostedEvents || []).find(e => e.id === this.selectedEventId)
            || null;
        if (!base) return this.selectedEventDetail || null;
        // OLD detail wins over mock list shape; mock list wins where detail is silent.
        return this.selectedEventDetail
            ? { ...base, ...this.selectedEventDetail }
            : base;
    }
    // Pass the eligible-audience payload to the detail component only for the host's own event.
    get selectedEligibleAudienceForView() {
        return this.isSelectedEventHosted ? this.selectedEligibleAudience : null;
    }
    get selectedEventTitle() { return this.selectedEvent ? this.selectedEvent.title : ''; }
    get selectedRegistration() { return this.selectedEvent ? this.selectedEvent.registration : null; }
    get selectedSurvey()       { return this.selectedEvent ? this.selectedEvent.survey : null; }

    handleTabChange(event)      { this.activeTab = event.detail.id; this.syncUrl(); }
    handleGoToUpcoming()        { this.activeTab = 'upcoming'; this.syncUrl(); this._scrollTop(); }
    // "View All" on the rail's Registered Events card -> dedicated Registered
    // Events page. basePath resolves the live community prefix (e.g. /alumninew),
    // so the slug must match the page's URL exactly ('registered-events').
    handleViewAllRegistered() {
        const target = basePath + '/registered-events';
        try { window.location.assign(target); } catch (e) { window.location.href = target; }
    }
    // Rail "View All" on Hosted Events → the Hosted tab board.
    handleViewAllHosted() {
        this.view = 'board';
        this.activeTab = 'hosted';
        this.loadHostedEvents();
        this.syncUrl();
        this._scrollTop();
    }
    // Rail Hosted row click → open that event's (host) detail to manage it.
    handleHostedClick(event) {
        const id = event && event.detail && event.detail.id;
        if (id) this.handleEventClick({ detail: { id } });
    }
    _scrollTop() { try { window.scrollTo({ top: 0, behavior: 'auto' }); } catch (e) { /* ignore */ } }
    handleCategoryChange(event) { this.activeCategory = event.detail.id; }

    handleEventClick(event) {
        const id = event.detail && event.detail.id !== undefined ? event.detail.id : event.detail;
        // Save scroll position before leaving board so handleBackToBoard can restore it.
        this._boardScrollY = (typeof window !== 'undefined' && window.scrollY) || 0;
        this.selectedEventId = id;
        this.selectedEventDetail = null;
        this.selectedEligibleAudience = null;
        // Only call OLD detail Apex for real Salesforce IDs (mock ids are numbers).
        if (typeof id === 'string' && id.length >= 15) {
            // Eligible Audience is a host/admin-only view — fetch only for the host's own event.
            if (this.isSelectedEventHosted) {
                getEventEligibleAudience({ eventId: id })
                    .then(res => { this.selectedEligibleAudience = res; })
                    .catch(err => {
                        // eslint-disable-next-line no-console
                        console.error('KenPortalEventController.getEventEligibleAudience error', err);
                    });
            }
            getEventDetails({ recordId: id })
                // Merge (not replace) so a decorations response that landed first isn't wiped.
                .then(d => { this.selectedEventDetail = { ...(this.selectedEventDetail || {}), ...this.mapEventDetail(d) }; })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('KenPortalEventController.getEventDetails error', err);
                });
            getEventDetailDecorations({ recordId: id })
                .then(dec => {
                    const decorated = this.mapEventDecorations(dec);
                    // Merge into the detail object — preserve already-resolved fields.
                    this.selectedEventDetail = { ...(this.selectedEventDetail || {}), ...decorated };
                })
                .catch(err => {
                    // eslint-disable-next-line no-console
                    console.error('KenPortalEventController.getEventDetailDecorations error', err);
                });
        }
        this.view = 'detail';
        this.syncUrl();
        try { window.scrollTo({ top: 0, behavior: 'instant' }); } catch (e) { window.scrollTo(0, 0); }
    }
    handleViewRegistration() {
        if (!this.selectedEvent) return;
        this.view = 'registration';
        this.syncUrl();
        try { window.scrollTo({ top: 0, behavior: 'instant' }); } catch (e) { window.scrollTo(0, 0); }
    }
    handleViewQuestionnaire() {
        if (!this.selectedEvent) return;
        this.view = 'questionnaire';
        this.syncUrl();
        try { window.scrollTo({ top: 0, behavior: 'instant' }); } catch (e) { window.scrollTo(0, 0); }
    }
    handleBackToBoard() {
        this.view = 'board';
        this.selectedEventId = null;
        this.selectedEventDetail = null;
        this.syncUrl();
        // Restore scroll position of the board on back-nav.
        const y = this._boardScrollY || 0;
        if (typeof window !== 'undefined' && window.requestAnimationFrame) {
            window.requestAnimationFrame(() => { try { window.scrollTo(0, y); } catch (e) { /* ignore */ } });
        }
    }
    handleBackToDetail() {
        this.view = 'detail';
        this.syncUrl();
    }

    handleRsvpFromDetail() { this.view = 'rsvp'; this.syncUrl(); }
    handleHostEvent()      { this.view = 'host'; this.syncUrl(); }
    handleClose(event)     {
        const submitted = event && event.detail && event.detail.submitted;
        this.view = 'board';
        if (submitted) {
            // The rebuilt host wizard (kenEventHostWizardV2) saves the event itself via
            // KenEventFormController and flips it to Pending Approval, then fires `close`
            // with submitted:true. Route the host to their Hosted tab + refresh so the new
            // pending event is immediately visible.
            this.showToast('Event submitted for approval!');
            this.activeTab = 'hosted';
            this.loadEvents();
            this.loadHostedEvents();
            this._scrollTop();
        }
        this.syncUrl();
    }
    handleRsvpSubmit() {
        const ev = this.selectedEvent;
        const eventId = ev && ev.id;
        // Guard: missing constituentRoleId means user can't actually register — don't lie with a success toast.
        if (!this.constituentRoleId) {
            this.showToast('Cannot register — your profile is missing alumni role. Please complete onboarding.');
            this.view = 'detail';
            this.syncUrl();
            return;
        }
        // Mock-id fallback for UI prototyping only (real id but no role would have been caught above).
        if (!isSfId(eventId)) {
            this.showToast('Event registered successfully');
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { this.view = 'board'; this.syncUrl(); }, 1800);
            return;
        }
        // Fetch sessions for this event then register the user for all of them.
        getEventSessions({ EventId: eventId })
            .then(sessions => {
                const sessionIds = (sessions || []).map(s => s && s.Id).filter(Boolean);
                if (!sessionIds.length) {
                    this.showToast('Event registered successfully');
                    // eslint-disable-next-line @lwc/lwc/no-async-operation
                    setTimeout(() => { this.view = 'board'; this.syncUrl(); }, 1800);
                    return null;
                }
                return saveRegistrations({ sessionIds, constituentRoleId: this.constituentRoleId });
            })
            .then(() => {
                this.showToast('Event registered successfully');
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => { this.view = 'board'; this.syncUrl(); }, 1800);
            })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenPortalEventController.saveRegistrations error', err);
                this.showToast((err && err.body && err.body.message) || 'Could not register. Please try again.');
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => { this.view = 'board'; this.syncUrl(); }, 1500);
            });
    }
    handleCancelRegistration() {
        // Cancel all sessions tied to the current event (best-effort).
        const ev = this.selectedEvent;
        const eventId = ev && ev.id;
        if (!isSfId(eventId) || !this.constituentRoleId) {
            this.showToast('Registration cancelled');
            return;
        }
        getEventSessions({ EventId: eventId })
            .then(sessions => {
                const sessionIds = (sessions || []).map(s => s && s.Id).filter(Boolean);
                if (!sessionIds.length) {
                    this.showToast('Registration cancelled');
                    return null;
                }
                return cancelRegistrations({ sessionIds, constituentRoleId: this.constituentRoleId });
            })
            .then(() => { this.showToast('Registration cancelled'); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('KenPortalEventController.cancelRegistrations error', err);
                this.showToast((err && err.body && err.body.message) || 'Could not cancel. Please try again.');
            });
    }
    handleHostSubmit(event) {
        const formData = event && event.detail && event.detail.formData;
        if (!formData) {
            this.showToast('Missing form data — please try again');
            return;
        }
        const payload = this._mapFormDataToPayload(formData);
        createEventApex({ payload })
            .then((eventId) => {
                this.showToast('Event submitted for review!');
                this.loadEvents();
                this.loadHostedEvents();
                // Route the host to the Hosted tab so their new (pending) event is
                // immediately visible instead of an empty board.
                this.view = 'board';
                this.activeTab = 'hosted';
                this.syncUrl();
                this._scrollTop();
                // Persist Groups / Individuals / CSV / roles selections as a linked segmentation.
                return this._persistEventSegmentation(eventId, formData);
            })
            .catch((err) => {
                // eslint-disable-next-line no-console
                console.error('KenPortalEventController.createEvent error', err);
                const msg = (err && err.body && err.body.message) || (err && err.message) || 'Could not submit event. Please try again.';
                this.showToast(msg);
            });
    }

    // Builds an AudienceRequestDTO-shaped payload from the wizard's audienceDetail,
    // saves it as a Ken_Segmentation__c, and links it to the event via
    // Ken_Event_Segmentation__c. Mirrors the Survey module's _persistSegmentation.
    _persistEventSegmentation(eventId, formData) {
        const detail = (formData && formData.audienceDetail) || {};
        const groupIds = detail.groupIds || [];
        const individualIds = detail.individualIds || [];
        const csvEmails = detail.csvEmails || [];
        const roles = detail.roles || [];
        if (!isSfId(eventId) ||
            (groupIds.length === 0 && individualIds.length === 0 && csvEmails.length === 0 && roles.length === 0)) {
            return null;
        }
        const filters = [];
        if (individualIds.length) {
            filters.push({ id: 'individuals', fieldApi: 'Id', operator: 'in', value: individualIds.join(','), dataType: 'reference' });
        }
        const title = formData.eventTitle || formData.name || 'Event';
        const req = {
            audienceName: `${String(title).substring(0, 60)} Audience ${Date.now()}`,
            description: 'Auto-generated from the event target-audience selection.',
            targetRole: 'Alumni',
            targetObject: 'ConstituentRole',
            active: true,
            matchMode: 'OR',
            filters,
            // extra keys preserved verbatim in Definition_JSON__c for downstream resolution
            category: detail.category,
            selectedGroupIds: groupIds,
            selectedIndividualIds: individualIds,
            csvEmails: csvEmails,
            roles: roles
        };
        return saveSegmentation({ requestJson: JSON.stringify(req) })
            .then(segId => createEventSegmentation({ eventId, segmentationId: segId }))
            .then(() => { this.showToast('Audience segmentation saved'); })
            .catch(err => {
                // eslint-disable-next-line no-console
                console.error('saveSegmentation/createEventSegmentation error', err);
                this.showToast('Event saved — audience segmentation could not be saved.');
            });
    }
    handleHostSaveDraft(event) {
        const detail = (event && event.detail) || {};
        // Rebuilt host wizard saves its own draft via KenEventFormController and fires
        // `savedraft` with just {eventId}. Acknowledge + refresh; do NOT re-create.
        if (detail.eventId && !detail.formData) {
            this.showToast('Draft saved');
            this.loadHostedEvents();
            return;
        }
        const formData = detail.formData;
        if (!formData) { this.showToast('Draft saved'); this.loadHostedEvents(); return; }
        const payload = this._mapFormDataToPayload(formData);
        saveEventDraftApex({ payload })
            .then(() => {
                this.showToast('Draft saved');
                this.loadHostedEvents();
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => { this.view = 'board'; this.syncUrl(); }, 1000);
            })
            .catch((err) => {
                // eslint-disable-next-line no-console
                console.error('KenPortalEventController.saveEventDraft error', err);
                const msg = (err && err.body && err.body.message) || (err && err.message) || 'Could not save draft.';
                this.showToast(msg);
            });
    }
    _mapFormDataToPayload(formData) {
        // Wizard dispatches: eventTitle, category, eventType, language, description,
        // startDate, endDate, multiDay, feeType, baseFee, currency.
        // We also tolerate the more generic names in case the wizard grows.
        const isOnline = (formData.hostType || '') === 'Online';
        return {
            name: formData.eventTitle || formData.name || formData.title || formData.eventName,
            eventType: formData.category || formData.eventType,
            description: formData.description || formData.about,
            language: Array.isArray(formData.language) ? formData.language.join(';') : (formData.language || ''),
            // Offline events carry a venue; Online events leave Location blank.
            location: isOnline ? '' : (formData.location || formData.venue || ''),
            startDate: formData.startDate || formData.eventDate,
            endDate: formData.endDate,
            startTime: formData.startTime || '',
            endTime: formData.endTime || '',
            hostType: formData.hostType || '',
            meetingLink: isOnline ? (formData.meetingLink || '') : '',
            speakerDetails: formData.speakerDetails || '',
            whatToExpect: formData.whatToExpect || '',
            agenda: formData.agenda || '',
            imageUrl: formData.imageUrl || formData.coverImage,
            categories: Array.isArray(formData.categories) ? formData.categories.join(';') : (formData.categories || formData.category),
            // Multi-day per-day speakers → Apex creates one Ken_Schedule_Sessions__c per day
            // with the named speaker enrollments. Empty/single-day events omit this.
            multiDay: !!formData.multiDay,
            daySchedules: (formData.multiDay && Array.isArray(formData.daySchedules)) ? formData.daySchedules : []
        };
    }
    handleHostSaveExit() {
        this.showToast('Progress saved');
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.view = 'board'; this.syncUrl(); }, 800);
    }

    showToast(msg) {
        this.toastMsg = msg;
        this.toastVisible = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.toastVisible = false; }, 2200);
    }
}