import { LightningElement, track } from 'lwc';
/* ============================================================ *
 *  Host-an-Event 7-step wizard — PORT of kenPortalCreateEvent
 *  state/logic onto the new Figma UI. Wired to KenEventFormController
 *  (deployed + granted to Alumni_2_0). PHASE A: shell + stepper + Step 1.
 * ============================================================ */
import saveEvent from '@salesforce/apex/KenEventFormController.saveEvent';
import listSpeakerCandidates from '@salesforce/apex/KenAudienceEngineService.listSpeakerCandidates';
import uploadFileToRecord from '@salesforce/apex/KenEventFormController.uploadFileToRecord';
import getPicklistValues from '@salesforce/apex/KenEventFormController.getPicklistValues';
import createEventSchedule from '@salesforce/apex/KenEventFormController.createEventSchedule';
import deleteSessionsData from '@salesforce/apex/KenEventFormController.deleteSessionsData';
import createEventSegmentation from '@salesforce/apex/KenEventFormController.createEventSegmentation';
import getEventSessions from '@salesforce/apex/KenEventFormController.getEventSessions';
import updateFee from '@salesforce/apex/KenEventFormController.updateFee';
import saveEventSurveyJson from '@salesforce/apex/KenEventHostExtras.saveEventSurveyJson';
import sendSpeakerInvites from '@salesforce/apex/KenEventHostExtras.sendSpeakerInvites';
import saveQuestionnaireForSession from '@salesforce/apex/KenEventFormController.saveQuestionnaireForSession';
import saveFeedbackTriggerSettings from '@salesforce/apex/KenEventFormController.saveFeedbackTriggerSettings';

const QUESTION_TYPES = [
    { value: 'Multiple choice', label: 'Multiple choice' },
    { value: 'Short answer', label: 'Short answer' },
    { value: 'Rating', label: 'Rating' },
    { value: 'Yes/No', label: 'Yes / No' }
];
const TRIGGER_WHEN_OPTIONS = [
    { value: 'Immediately after the session', label: 'Immediately after the session' },
    { value: '1 hour after the session', label: '1 hour after the session' },
    { value: '1 day after the session', label: '1 day after the session' },
    { value: 'On event completion', label: 'On event completion' }
];

const LOCATION_TYPES = [{ value: 'online', label: 'Online' }, { value: 'onsite', label: 'Offline' }, { value: 'hybrid', label: 'Hybrid' }];

const SURVEY_QUESTION_TYPES = [
    { value: 'Multiple choice', label: 'Multiple choice' },
    { value: 'Checkbox', label: 'Checkbox' },
    { value: 'Short answer', label: 'Short answer' },
    { value: 'Rating', label: 'Rating' },
    { value: 'Yes/No', label: 'Yes / No' }
];
const STEPS = [
    'Event Setup', 'Target Audience', 'Schedule Setup',
    'Pre Event Surveys', 'Fee Setup', 'Feedback Form', 'Summary'
];
const MONTHS = ['January','February','March','April','May','June','July','August','September','October','November','December'];
const DOW = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const MAX_IMG_BYTES = 5 * 1024 * 1024;
const ALLOWED_IMG_TYPES = ['image/png', 'image/jpeg'];
const ALLOWED_IMG_EXTS = ['png', 'jpg', 'jpeg'];

export default class KenEventHostWizardV2 extends LightningElement {
    @track step = 1;
    @track audienceExpanded = false;   // Step 2 "Add New Audience" builder breaks out to full width
    @track errorMsg = '';
    @track saving = false;
    currentEventId = null;
    roleId = null;

    // ---- consolidated payload (all 7 steps; Phase A populates Step 1) ----
    @track ev = {
        title: '', category: '', language: '', maxParticipants: '',
        description: '', agenda: '',
        canBringGuests: 'no', maxGuests: 1,
        coverBase64: null, coverName: '', coverType: '',
        brochureBase64: null, brochureName: '', brochureType: ''
    };
    // Step 2-7 buckets (built out in later phases)
    @track audience = null;        // Step 2 (from canonical kenEventStepDetailsV2)
    @track sessionsByDate = {};    // Step 3
    @track activeDate = '';        // Step 3 active day tab
    _sessionSeq = 0;
    @track survey = { customSurvey: true, questions: [] };   // Step 4 — Pre Event Surveys
    _sqSeq = 0;
    @track pricing = { mode: '', overallFee: '', overallFree: false, sessionFees: {} };  // Step 5 (mode '' = no option chosen yet)
    @track feeSummaryOpen = false;   // Step 5 "Show summary" toggle (overall pricing)
    @track feeSessions = [];       // Step 5/6 — loaded from getEventSessions
    @track feedback = {};          // Step 6 — { [sessionId]: { triggerType, endDate, endTime, questions:[] } }
    @track activeFeedbackSessionId = null;
    _feedbackSnapshot = undefined;   // backup of the active form, for "Discard Changes"
    @track showFeedbackSavedToast = false;
    _qSeq = 0;
    @track showSuccess = false;

    // Add Speaker modal (Step 3)
    @track speakerModalOpen = false;
    @track speakerDraft = { name: '', email: '', description: '', imageBase64: null, imageName: '', imageType: '', accountId: null };
    @track speakerResults = [];
    @track speakerSearching = false;
    @track speakerEmailLocked = false;   // email read-only once a person is picked from search
    @track showSpeakerList = false;      // dropdown visibility (opens on focus, shows default list)
    _speakerSessionId = null;
    _speakerEditIdx = null;
    _spkSeq = 0;
    _spkTimer = null;
    _spkBlurTimer = null;

    // ---- date selection (Step 1 calendar / drives Step 3 day tabs) ----
    @track selectedDates = [];     // ISO yyyy-mm-dd, sorted
    @track viewYear;
    @track viewMonth;              // 0-11

    @track categoryOptions = [];
    @track languageOptions = [];
    @track tzPicklist = [];   // Timezone options loaded from the org Timezone picklist
    @track coverError = '';
    @track langMenuOpen = false;

    connectedCallback() {
        const now = new Date();
        this.viewYear = now.getFullYear();
        this.viewMonth = now.getMonth();
        try { this.roleId = window.localStorage.getItem('ConstituentRoleId'); } catch (e) { this.roleId = null; }
        this._loadPicklists();
        // Close the language multi-select menu when clicking anywhere outside it.
        this._closeLangMenu = () => { if (this.langMenuOpen) this.langMenuOpen = false; };
        window.addEventListener('click', this._closeLangMenu);
    }
    disconnectedCallback() {
        if (this._closeLangMenu) window.removeEventListener('click', this._closeLangMenu);
    }

    _loadPicklists() {
        getPicklistValues({ objectName: 'Ken_Event_Master__c', fieldNames: ['Event_Type__c', 'Language__c', 'Timezone__c'] })
            .then(res => {
                this.categoryOptions = this._fmt(res && res.Event_Type__c);
                this.languageOptions = this._fmt(res && res.Language__c);
                // Timezone options are sourced from the org picklist so the saved value is always
                // the exact restricted-picklist value (no UI/DB format mismatch).
                this.tzPicklist = this._fmt(res && res.Timezone__c);
            })
            .catch(() => { this.categoryOptions = []; this.languageOptions = []; this.tzPicklist = []; });
    }
    _fmt(list) {
        return (list || []).map(o => ({
            value: o.value || o.Value || o.label || o, label: o.label || o.Label || o.value || o
        }));
    }

    /* ================= stepper / progress ================= */
    get stepperItems() {
        return STEPS.map((label, i) => {
            const num = i + 1;
            const done = this.step > num;
            const active = this.step === num;
            return {
                num, label,
                showCheck: done,
                stepClass: 'hw-step' + (active ? ' hw-step--active' : '') + (done ? ' hw-step--done' : ''),
                showConnector: i < STEPS.length - 1
            };
        });
    }
    get progressStyle() { return `width:${(this.step / STEPS.length) * 100}%;`; }
    get stepCounter() { return `Step ${this.step} out of ${STEPS.length}`; }

    // 1 Event · 2 Audience · 3 Schedule · 4 Pre Event Surveys · 5 Fee · 6 Feedback · 7 Summary
    get isStep1() { return this.step === 1; }
    get isStep2() { return this.step === 2; }
    get isStep3() { return this.step === 3; }
    get isStep4() { return this.step === 4; }   // Pre Event Surveys
    get isStep5() { return this.step === 5; }   // Fee Setup
    get isStep6() { return this.step === 6; }   // Feedback Form
    get isStep7() { return this.step === 7; }   // Summary
    get showBack() { return this.step > 1; }
    get primaryLabel() {
        if (this.step === 7) return 'Confirm & Submit';
        if (this.step === 1) return 'Save and Proceed';
        return 'Next';
    }

    /* ================= Step 1 — category/language ================= */
    get categorySelectOptions() {
        return this.categoryOptions.map(o => ({ ...o, selected: o.value === this.ev.category }));
    }
    // ---- Language of Delivery: multi-select (Language__c is a MultiselectPicklist) ----
    // ev.language is stored as a ';'-joined string, the format Salesforce expects.
    get _languageArray() {
        return this.ev.language ? this.ev.language.split(';').filter(Boolean) : [];
    }
    get hasLanguages() { return this._languageArray.length > 0; }
    get selectedLanguageChips() {
        const sel = this._languageArray;
        return this.languageOptions
            .filter(o => sel.indexOf(o.value) > -1)
            .map(o => ({ value: o.value, label: o.label }));
    }
    get languageMenuOptions() {
        const sel = this._languageArray;
        return this.languageOptions.map(o => {
            const checked = sel.indexOf(o.value) > -1;
            return { ...o, selected: checked, boxClass: 'hw-ms__box' + (checked ? ' hw-ms__box--on' : '') };
        });
    }
    get summaryLanguages() { return this._languageArray.join(', ') || '—'; }

    toggleLangMenu(e) {
        if (e) e.stopPropagation();
        this.langMenuOpen = !this.langMenuOpen;
    }
    toggleLanguage(e) {
        e.stopPropagation();
        const v = e.currentTarget.dataset.value;
        if (!v) return;
        const sel = this._languageArray;
        const idx = sel.indexOf(v);
        if (idx > -1) sel.splice(idx, 1); else sel.push(v);
        this.ev = { ...this.ev, language: sel.join(';') };
    }
    removeLanguage(e) {
        e.stopPropagation();
        const v = e.currentTarget.dataset.value;
        this.ev = { ...this.ev, language: this._languageArray.filter(x => x !== v).join(';') };
    }
    get guestsYes() { return this.ev.canBringGuests === 'yes'; }
    get guestsNo() { return this.ev.canBringGuests !== 'yes'; }

    handleField(e) {
        const f = e.target.dataset.field;
        if (!f) return;
        this.ev = { ...this.ev, [f]: e.target.value };
        if (this.errorMsg) this.errorMsg = '';
    }
    selectGuests(e) {
        // Yes/No radio: value is 'yes' or 'no'
        this.ev = { ...this.ev, canBringGuests: e.target.value };
    }
    incGuests() {
        this.ev = { ...this.ev, maxGuests: (Number(this.ev.maxGuests) || 0) + 1 };
    }
    decGuests() {
        this.ev = { ...this.ev, maxGuests: Math.max(1, (Number(this.ev.maxGuests) || 1) - 1) };
    }
    aiAssist(e) {
        const f = e.currentTarget.dataset.field;
        const add = '\n\nJoin us for an engaging session — more details to follow.';
        this.ev = { ...this.ev, [f]: (this.ev[f] || '') + add };
    }

    /* ================= Step 1 — files (cover + brochure) ================= */
    get hasCover() { return !!this.ev.coverName; }
    get coverLabel() { return this.ev.coverName || 'Choose a cover photo (Optional)'; }
    get coverPreviewUrl() {
        return this.ev.coverBase64 ? `data:${this.ev.coverType || 'image/png'};base64,${this.ev.coverBase64}` : '';
    }
    get hasBrochure() { return !!this.ev.brochureName; }
    get brochureLabel() { return this.ev.brochureName || 'Upload a brochure (Optional)'; }

    handleCover(e) {
        this.coverError = '';
        const file = e.target.files && e.target.files[0];
        if (!file) return;
        // Enforce PNG/JPEG only — the `accept` attribute just filters the picker, it doesn't validate.
        const ext = (file.name.split('.').pop() || '').toLowerCase();
        const typeOk = ALLOWED_IMG_TYPES.indexOf((file.type || '').toLowerCase()) > -1;
        const extOk = ALLOWED_IMG_EXTS.indexOf(ext) > -1;
        if (!typeOk && !extOk) { this.coverError = 'Only PNG or JPEG images are allowed.'; e.target.value = ''; return; }
        if (file.size > MAX_IMG_BYTES) { this.coverError = 'Image too large (max 5 MB).'; e.target.value = ''; return; }
        this._readBase64(file).then(b64 => {
            this.ev = { ...this.ev, coverBase64: b64, coverName: file.name, coverType: file.type || 'image/png' };
        });
    }
    handleBrochure(e) {
        const file = e.target.files && e.target.files[0];
        if (!file) return;
        this._readBase64(file).then(b64 => {
            this.ev = { ...this.ev, brochureBase64: b64, brochureName: file.name, brochureType: file.type || 'application/pdf' };
        });
    }
    removeCover() { this.ev = { ...this.ev, coverBase64: null, coverName: '', coverType: '' }; }
    removeBrochure() { this.ev = { ...this.ev, brochureBase64: null, brochureName: '', brochureType: '' }; }
    _readBase64(file) {
        return new Promise((resolve, reject) => {
            const r = new FileReader();
            r.onload = () => resolve(String(r.result).split(',')[1]);
            r.onerror = () => reject(r.error);
            r.readAsDataURL(file);
        });
    }

    /* ================= Step 1 — calendar (multi-day) ================= */
    get calendarLabel() { return `${MONTHS[this.viewMonth]} ${this.viewYear}`; }
    get dowHeaders() { return DOW.map((d, i) => ({ k: 'dow' + i, d })); }
    get calendarCells() {
        const first = new Date(this.viewYear, this.viewMonth, 1);
        const startDow = first.getDay();
        const daysInMonth = new Date(this.viewYear, this.viewMonth + 1, 0).getDate();
        const todayIso = this._iso(new Date());
        const cells = [];
        for (let i = 0; i < startDow; i++) cells.push({ k: 'blank' + i, blank: true, cls: 'hw-cal__cell hw-cal__cell--blank' });
        for (let d = 1; d <= daysInMonth; d++) {
            const iso = this._isoYMD(this.viewYear, this.viewMonth, d);
            const sel = this.selectedDates.indexOf(iso) > -1;
            cells.push({
                k: iso, blank: false, day: d, iso,
                cls: 'hw-cal__cell' + (sel ? ' hw-cal__cell--sel' : '') + (iso === todayIso ? ' hw-cal__cell--today' : '')
            });
        }
        return cells;
    }
    get selectedDatePills() {
        return this.selectedDates.map(iso => ({ iso, label: this._pretty(iso) }));
    }
    get hasDates() { return this.selectedDates.length > 0; }
    get isMultiDay() { return this.selectedDates.length > 1; }

    prevMonth() { if (this.viewMonth === 0) { this.viewMonth = 11; this.viewYear -= 1; } else { this.viewMonth -= 1; } }
    nextMonth() { if (this.viewMonth === 11) { this.viewMonth = 0; this.viewYear += 1; } else { this.viewMonth += 1; } }
    toggleDate(e) {
        const iso = e.currentTarget.dataset.iso;
        if (!iso) return;
        const idx = this.selectedDates.indexOf(iso);
        let next = this.selectedDates.slice();
        if (idx > -1) next.splice(idx, 1); else next.push(iso);
        next.sort();
        this.selectedDates = next;
    }
    removeDate(e) {
        const iso = e.currentTarget.dataset.iso;
        this.selectedDates = this.selectedDates.filter(d => d !== iso);
    }
    _iso(d) { return this._isoYMD(d.getFullYear(), d.getMonth(), d.getDate()); }
    _isoYMD(y, m, d) { return `${y}-${String(m + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`; }
    _pretty(iso) {
        const [y, m, d] = iso.split('-').map(Number);
        return `${d} ${MONTHS[m - 1].slice(0, 3)}, ${y}`;
    }

    /* ================= validation ================= */
    _validateStep1() {
        const miss = [];
        if (!this.ev.title || !this.ev.title.trim()) miss.push('Event Title');
        if (!this.ev.category) miss.push('Category');
        if (!this.hasDates) miss.push('at least one Date');
        if (this.ev.canBringGuests === 'yes' && (!this.ev.maxGuests || Number(this.ev.maxGuests) < 1)) miss.push('Number of Guests');
        return miss;
    }

    /* ================= Step 2 — Target Audience (canonical) ================= */
    get audienceData() { return this.audience; }
    handleAudienceChange(e) {
        const d = e.detail || {};
        if (d.field === 'audienceDetail') this.audience = d.value;
    }
    // Step 2 builder widens the centred content column to full width.
    handleAudienceExpand(e) { this.audienceExpanded = !!(e.detail && e.detail.expanded); }
    get bodyInnerClass() { return 'hw-body__inner' + (this.isStep2 && this.audienceExpanded ? ' hw-body__inner--wide' : ''); }
    async _persistStep2() {
        // Preserve canonical persistence: link each selected group/segmentation to the event.
        const a = this.audience || {};
        const ids = (a.groupIds && a.groupIds.length ? a.groupIds : (Array.isArray(a.groups) ? a.groups : [])) || [];
        for (const segId of ids) {
            if (!segId) continue;
            // Defensive: a wrong-typed id shouldn't block the wizard.
            // eslint-disable-next-line no-await-in-loop
            await createEventSegmentation({ eventId: this.currentEventId, segmentationId: segId }).catch(() => {});
        }
    }

    /* ================= Step 3 — Schedule / Sessions / Speakers ================= */
    get timezoneOptions() { return this.tzPicklist; }
    get dayTabs() {
        return this.selectedDates.map(iso => {
            const sessions = this.sessionsByDate[iso] || [];
            // A day is "complete" when it has sessions and none are missing the basics.
            const complete = sessions.length > 0 && sessions.every(s => {
                if (this._sessionIsEmpty(s)) return false;
                const loc = s.locationType || 'online';
                const linkOk = !(loc === 'online' || loc === 'hybrid') || (s.sessionLink && s.sessionLink.trim());
                return s.title && s.title.trim() && s.startTime && linkOk;
            });
            const active = iso === this.activeDate;
            return {
                iso, label: this._pretty(iso),
                cls: 'hw-daytab' + (active ? ' hw-daytab--active' : '') + (complete && !active ? ' hw-daytab--done' : '')
            };
        });
    }
    get activeSessions() {
        // Session numbering restarts per day: each date's sessions are Session 1, 2, 3 …
        const list = this.sessionsByDate[this.activeDate] || [];
        return list.map((s, i) => ({
            ...s,
            index: i + 1,
            cardClass: 'hw-session' + (s.expanded ? ' hw-session--open' : ''),
            chevronClass: s.expanded ? 'hw-session__chev hw-session__chev--open' : 'hw-session__chev',
            tzOptions: this.tzPicklist.map(t => ({ value: t.value, label: t.label, selected: t.value === s.timeZone })),
            locOptions: LOCATION_TYPES.map(o => ({ ...o, selected: o.value === s.locationType })),
            showVenue: s.locationType === 'onsite' || s.locationType === 'hybrid',
            showLink: s.locationType === 'online' || s.locationType === 'hybrid',
            showLocationRow: !!s.locationType,
            radioName: 'loc-' + s.id,
            hasSpeakers: (s.speakers || []).length > 0,
            speakerRows: (s.speakers || []).map((sp, j) => ({
                ...sp, key: s.id + '-sp' + j, idx: j, sNo: j + 1,
                hasImage: !!sp.imageName,
                imageLabel: sp.imageName || '—',
                imageUrl: sp.imageBase64 ? `data:${sp.imageType || 'image/png'};base64,${sp.imageBase64}` : '',
                descriptionText: sp.description || '—'
            }))
        }));
    }
    get hasActiveSessions() { return (this.sessionsByDate[this.activeDate] || []).length > 0; }

    _newSession() {
        this._sessionSeq += 1;
        return {
            id: 'sess-' + this._sessionSeq, title: '', timeZone: '', startTime: '', endTime: '',
            maxParticipants: '', agenda: '', locationType: 'online', locationAddress: '', sessionLink: '',
            speakers: [], expanded: true
        };
    }
    _ensureSchedule() {
        if (!this.selectedDates.length) return;
        if (!this.activeDate || this.selectedDates.indexOf(this.activeDate) === -1) this.activeDate = this.selectedDates[0];
        const next = { ...this.sessionsByDate };
        // Seed one open session per day so the form shows by default (no need to click +).
        // Only for dates not yet initialized — a day the user emptied stays empty.
        this.selectedDates.forEach(d => { if (!next[d]) next[d] = [this._newSession()]; });
        this.sessionsByDate = next;
    }
    selectDay(e) { this.activeDate = e.currentTarget.dataset.iso; }
    addSession() {
        const list = (this.sessionsByDate[this.activeDate] || []).slice();
        list.push(this._newSession());
        this.sessionsByDate = { ...this.sessionsByDate, [this.activeDate]: list };
    }
    _updateSession(id, mut) {
        const list = (this.sessionsByDate[this.activeDate] || []).map(s => (s.id === id ? mut({ ...s }) : s));
        this.sessionsByDate = { ...this.sessionsByDate, [this.activeDate]: list };
    }
    toggleSession(e) { const id = e.currentTarget.dataset.id; this._updateSession(id, s => { s.expanded = !s.expanded; return s; }); }
    deleteSession(e) {
        const id = e.currentTarget.dataset.id;
        const list = (this.sessionsByDate[this.activeDate] || []).filter(s => s.id !== id);
        this.sessionsByDate = { ...this.sessionsByDate, [this.activeDate]: list };
    }
    sessionField(e) {
        const id = e.target.dataset.id, f = e.target.dataset.field, v = e.target.value;
        this._updateSession(id, s => { s[f] = v; return s; });
        if (this.errorMsg) this.errorMsg = '';   // clear stale validation banner once the user edits
    }
    toggleShareInvite(e) {
        const id = e.target.dataset.id, v = e.target.checked;
        this._updateSession(id, s => { s.shareEmailInvite = v; return s; });
    }
    // Open the native time picker on clicking anywhere in the field (not just the clock icon).
    openTimePicker(e) {
        try { if (e.target && e.target.showPicker) e.target.showPicker(); } catch (err) { /* ignore */ }
    }
    sessionAi(e) {
        const id = e.currentTarget.dataset.id;
        this._updateSession(id, s => { s.agenda = (s.agenda || '') + '\n\nAgenda highlights to be finalised shortly.'; return s; });
    }
    get rteFormats() { return ['bold', 'italic', 'underline', 'list', 'bullet', 'indent', 'align', 'link', 'clean']; }
    agendaChange(e) {
        const id = e.target.dataset.id;
        const v = e.target.value;
        this._updateSession(id, s => { s.agenda = v; return s; });
        if (this.errorMsg) this.errorMsg = '';
    }
    speakerAboutChange(e) {
        this.speakerDraft = { ...this.speakerDraft, description: e.target.value };
    }
    removeSpeaker(e) {
        const id = e.currentTarget.dataset.id, idx = parseInt(e.currentTarget.dataset.idx, 10);
        this._updateSession(id, s => { s.speakers = s.speakers.filter((sp, j) => j !== idx); return s; });
    }

    /* ----- Add / Edit Speaker modal ----- */
    get speakerModalTitle() { return this._speakerEditIdx == null ? 'Add a Speaker' : 'Edit Speaker'; }
    openAddSpeaker(e) {
        this._speakerSessionId = e.currentTarget.dataset.id;
        this._speakerEditIdx = null;
        this.speakerDraft = { name: '', email: '', description: '', imageBase64: null, imageName: '', imageType: '', accountId: null };
        this.speakerEmailLocked = false;
        this.speakerResults = [];
        this.speakerSearching = false;
        this.showSpeakerList = false;
        this.speakerModalOpen = true;
    }
    openEditSpeaker(e) {
        const id = e.currentTarget.dataset.id, idx = parseInt(e.currentTarget.dataset.idx, 10);
        const list = this.sessionsByDate[this.activeDate] || [];
        const sess = list.find(s => s.id === id);
        const sp = sess && sess.speakers ? sess.speakers[idx] : null;
        if (!sp) return;
        this._speakerSessionId = id;
        this._speakerEditIdx = idx;
        this.speakerDraft = { name: sp.name || '', email: sp.email || '', description: sp.description || '', imageBase64: sp.imageBase64 || null, imageName: sp.imageName || '', imageType: sp.imageType || '', accountId: sp.accountId || null };
        this.speakerEmailLocked = !!(sp.accountId && sp.email);
        this.speakerResults = [];
        this.speakerSearching = false;
        this.showSpeakerList = false;
        this.speakerModalOpen = true;
    }
    cancelSpeaker() {
        this.speakerModalOpen = false; this._speakerSessionId = null; this._speakerEditIdx = null;
        this.speakerResults = []; this.speakerSearching = false; this.speakerEmailLocked = false; this.showSpeakerList = false;
    }
    stopBubble(e) { e.stopPropagation(); }
    speakerDraftField(e) {
        const f = e.target.dataset.field;
        this.speakerDraft = { ...this.speakerDraft, [f]: e.target.value };
    }
    /* ----- Speaker name lookup: default list on focus, filter as you type ----- */
    get hasSpeakerResults() { return (this.speakerResults || []).length > 0; }
    get speakerResultRows() { return (this.speakerResults || []).map(p => ({ id: p.id, name: p.name, email: p.email || '' })); }
    get showSpeakerEmpty() { return this.showSpeakerList && !this.speakerSearching && !this.hasSpeakerResults; }
    speakerNameFocus() {
        this.showSpeakerList = true;
        if (!this.hasSpeakerResults && !this.speakerSearching) this._loadSpeakerCandidates(this.speakerDraft.name || '');
    }
    speakerNameBlur() {
        // Delay closing so a click/mousedown on an option still registers.
        if (this._spkBlurTimer) clearTimeout(this._spkBlurTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._spkBlurTimer = setTimeout(() => { this.showSpeakerList = false; }, 200);
    }
    speakerNameInput(e) {
        const term = e.target.value || '';
        // Typing a name clears any prior selection so the email becomes editable again.
        this.speakerDraft = { ...this.speakerDraft, name: term, accountId: null };
        this.speakerEmailLocked = false;
        this.showSpeakerList = true;
        if (this._spkTimer) clearTimeout(this._spkTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._spkTimer = setTimeout(() => this._loadSpeakerCandidates(term), 250);
    }
    _loadSpeakerCandidates(term) {
        this.speakerSearching = true;
        const seq = ++this._spkSeq;
        listSpeakerCandidates({ searchTerm: term || '', limitSize: 20 })
            .then(rows => { if (seq !== this._spkSeq) return; this.speakerResults = rows || []; this.speakerSearching = false; })
            .catch(() => { if (seq !== this._spkSeq) return; this.speakerResults = []; this.speakerSearching = false; });
    }
    pickSpeaker(e) {
        const el = e.currentTarget;
        const email = el.dataset.email || '';
        this.speakerDraft = { ...this.speakerDraft, name: el.dataset.name || '', email, accountId: el.dataset.id || null };
        this.speakerEmailLocked = !!email;   // lock only when the selected person has an email on file
        this.showSpeakerList = false;
        this.speakerResults = [];
        this.speakerSearching = false;
        this._spkSeq++;
    }
    speakerImage(e) {
        const file = e.target.files && e.target.files[0];
        if (!file) return;
        this._readBase64(file).then(b64 => {
            this.speakerDraft = { ...this.speakerDraft, imageBase64: b64, imageName: file.name, imageType: file.type || 'image/png' };
        });
    }
    get speakerImageLabel() { return this.speakerDraft.imageName || 'Choose image'; }
    get speakerSaveDisabled() { return !(this.speakerDraft.name && this.speakerDraft.name.trim()); }
    saveSpeaker() {
        if (this.speakerSaveDisabled) return;
        const sp = { ...this.speakerDraft };
        const id = this._speakerSessionId;
        const editIdx = this._speakerEditIdx;
        this._updateSession(id, s => {
            const list = (s.speakers || []).slice();
            if (editIdx == null) list.push(sp); else list[editIdx] = sp;
            s.speakers = list;
            return s;
        });
        this.speakerModalOpen = false;
        this._speakerSessionId = null;
        this._speakerEditIdx = null;
    }

    _timeJson(hhmm) { return hhmm ? `${hhmm}:00.000Z` : null; }   // Apex Time JSON format
    _buildScheduleJson() {
        const rows = [];
        this.selectedDates.forEach(iso => {
            (this.sessionsByDate[iso] || []).forEach(s => {
                if (this._sessionIsEmpty(s)) return;   // don't persist untouched auto-seeded sessions
                rows.push({
                    Id: s.recordId || null,
                    eventId: this.currentEventId,
                    name: s.title || 'Session',
                    agenda: s.agenda || null,
                    startDate: iso,
                    endDate: iso,
                    startTime: this._timeJson(s.startTime),
                    endTime: this._timeJson(s.endTime),
                    locationType: s.locationType || 'online',
                    locationAddress: s.locationAddress || null,
                    sessionLink: s.sessionLink || null,
                    isPortal: true,
                    noFee: true,
                    // captured for later schema (timezone/maxParticipants have no native session field yet)
                    timeZone: s.timeZone || null,
                    maxParticipants: s.maxParticipants ? Number(s.maxParticipants) : null,
                    speakers: (s.speakers || []).filter(sp => sp.name && sp.name.trim()).map(sp => ({
                        Id: null, name: sp.name, description: sp.description || '', accountId: null
                    }))
                });
            });
        });
        return rows;
    }
    _sessionIsEmpty(s) {
        // An auto-seeded, untouched session — nothing typed/selected. Ignored by validation/save.
        return !((s.title && s.title.trim()) || s.startTime || s.endTime || s.maxParticipants ||
                 (s.locationAddress && s.locationAddress.trim()) || (s.sessionLink && s.sessionLink.trim()) ||
                 (s.agenda && s.agenda.trim()) || (s.speakers && s.speakers.some(sp => sp.name && sp.name.trim())));
    }
    _validateStep3() {
        let validCount = 0;
        for (const iso of this.selectedDates) {
            const label = this._pretty(iso);
            const list = this.sessionsByDate[iso] || [];
            for (let j = 0; j < list.length; j++) {
                const s = list[j];
                // Every session must be completed before moving on — empties block too
                // (delete an unwanted session with the trash icon instead).
                // Session number restarts per day, matching the card header (e.g. "Session 2 (18 Jun, 2026)").
                const where = `Session ${j + 1} (${label})`;
                if (!s.title || !s.title.trim()) return this._failSession(iso, s.id, `${where}: add a Session Title.`);
                if (!s.startTime) return this._failSession(iso, s.id, `${where}: add a Start Time.`);
                if (s.endTime && s.endTime <= s.startTime) return this._failSession(iso, s.id, `${where}: End Time must be after Start Time.`);
                const loc = s.locationType || 'online';
                if ((loc === 'online' || loc === 'hybrid') && (!s.sessionLink || !s.sessionLink.trim())) {
                    return this._failSession(iso, s.id, `${where}: add a meeting link for online sessions.`);
                }
                validCount++;
            }
        }
        if (validCount === 0) return 'Add at least one session.';
        return '';
    }
    // Surface the offending session: switch to its day and expand it so the user sees the gap.
    _failSession(iso, sid, msg) {
        this.activeDate = iso;
        const list = (this.sessionsByDate[iso] || []).map(s => (s.id === sid ? { ...s, expanded: true } : s));
        this.sessionsByDate = { ...this.sessionsByDate, [iso]: list };
        return msg;
    }
    async _persistStep3() {
        const rows = this._buildScheduleJson();
        // Clear previously-saved sessions for this event first, so re-visiting Step 3
        // (Back → Next) replaces them instead of inserting duplicates. Empty date list
        // = delete ALL sessions for the event (safe: a draft has no registrations yet).
        if (this.currentEventId) {
            await deleteSessionsData({ selectedDates: [], eventId: this.currentEventId }).catch(() => {});
        }
        await createEventSchedule({ records: JSON.stringify(rows) });
    }

    /* ================= Step 4 — Pre Event Surveys ================= */
    get customSurveyOn() { return !!this.survey.customSurvey; }
    get surveyQuestions() {
        return (this.survey.questions || []).map((q, i) => {
            const opts = Array.isArray(q.options) ? q.options : [];
            const isCheckbox = q.type === 'Checkbox';
            const isChoice = q.type === 'Multiple choice' || isCheckbox;
            return {
                ...q, number: i + 1,
                showOptions: isChoice,
                isCheckbox,
                typeOptions: SURVEY_QUESTION_TYPES.map(t => ({ ...t, selected: t.value === q.type })),
                optionRows: opts.map((o, j) => ({
                    key: q.id + '-o' + j, idx: j, letter: String.fromCharCode(97 + j) + ')', value: o,
                    markClass: isCheckbox ? 'hw-fbopt__box' : 'hw-fbopt__radio'
                }))
            };
        });
    }
    toggleCustomSurvey(e) { this.survey = { ...this.survey, customSurvey: e.target.checked }; }
    _updateSurvey(mut) { this.survey = mut({ ...this.survey, questions: (this.survey.questions || []).slice() }); }
    addSurveyQuestion() {
        this._sqSeq += 1;
        this._updateSurvey(s => { s.questions = s.questions.concat([{ id: 'sq-' + this._sqSeq, type: 'Multiple choice', text: '', required: false, options: [''] }]); return s; });
    }
    surveyQuestionField(e) {
        const id = e.target.dataset.id, fld = e.target.dataset.field, v = e.target.value;
        this._updateSurvey(s => {
            s.questions = s.questions.map(q => {
                if (q.id !== id) return q;
                const next = { ...q, [fld]: v };
                if (fld === 'type' && (v === 'Multiple choice' || v === 'Checkbox') && !(Array.isArray(q.options) && q.options.length)) next.options = [''];
                return next;
            });
            return s;
        });
    }
    toggleSurveyRequired(e) {
        const id = e.target.dataset.id, v = e.target.checked;
        this._updateSurvey(s => { s.questions = s.questions.map(q => (q.id === id ? { ...q, required: v } : q)); return s; });
    }
    removeSurveyQuestion(e) {
        const id = e.currentTarget.dataset.id;
        this._updateSurvey(s => { s.questions = s.questions.filter(q => q.id !== id); return s; });
    }
    addSurveyOption(e) {
        const id = e.currentTarget.dataset.id;
        this._updateSurvey(s => { s.questions = s.questions.map(q => (q.id === id ? { ...q, options: [...(q.options || []), ''] } : q)); return s; });
    }
    removeSurveyOption(e) {
        const id = e.currentTarget.dataset.id, idx = parseInt(e.currentTarget.dataset.idx, 10);
        this._updateSurvey(s => { s.questions = s.questions.map(q => (q.id === id ? { ...q, options: (q.options || []).filter((o, j) => j !== idx) } : q)); return s; });
    }
    surveyOptionInput(e) {
        const id = e.target.dataset.id, idx = parseInt(e.target.dataset.idx, 10), v = e.target.value;
        this._updateSurvey(s => { s.questions = s.questions.map(q => (q.id === id ? { ...q, options: (q.options || []).map((o, j) => (j === idx ? v : o)) } : q)); return s; });
    }
    async _persistStep4() {
        await saveEventSurveyJson({ eventId: this.currentEventId, surveyJson: JSON.stringify(this.survey) });
    }

    /* ================= Step 5 — Fee Setup ================= */
    get isSessionWise() { return this.pricing.mode === 'session'; }
    get isOverall() { return this.pricing.mode === 'overall'; }
    get noModeChosen() { return !this.pricing.mode; }
    // Option cards (highlighted box + check icon when selected).
    get sessionCardClass() { return 'hw-feeopt' + (this.isSessionWise ? ' hw-feeopt--on' : ''); }
    get overallCardClass() { return 'hw-feeopt' + (this.isOverall ? ' hw-feeopt--on' : ''); }

    // Session-wise pricing grouped by day, with sessions numbered per day (Session 1, Session 2 …).
    get pricingDays() {
        const byDate = {};
        const order = [];
        this.feeSessions.forEach(s => {
            const d = s.date || '';
            if (!byDate[d]) { byDate[d] = []; order.push(d); }
            byDate[d].push(s);
        });
        order.sort();
        return order.map(d => ({
            key: d || 'undated',
            label: d ? this._pretty(d) : '',
            sessions: byDate[d].map((s, i) => {
                const f = this.pricing.sessionFees[s.id] || {};
                return { id: s.id, sNo: 'Session ' + (i + 1), name: s.name, fee: f.fee || '', free: !!f.free, feeDisabled: !!f.free };
            })
        }));
    }
    get overallFeeDisabled() { return this.pricing.overallFree; }

    get sessionFeesSubtotal() {
        let total = 0;
        this.feeSessions.forEach(s => {
            const f = this.pricing.sessionFees[s.id] || {};
            if (!f.free) total += Number(f.fee || 0);
        });
        return total;
    }
    get overallBase() { return this.pricing.overallFree ? 0 : Number(this.pricing.overallFee || 0); }

    get totalEventCost() {
        return this.isOverall ? this.overallBase : this.sessionFeesSubtotal;
    }
    get totalEventCostDisplay() { return this._money(this.totalEventCost); }
    // "Show summary" (overall pricing) expands the day & session schedule, with times.
    get feeSummaryDays() {
        return this.selectedDates.map(iso => {
            const sessions = (this.sessionsByDate[iso] || []).filter(s => !this._sessionIsEmpty(s));
            return {
                key: iso,
                label: this._pretty(iso),
                sessions: sessions.map((s, i) => ({
                    key: s.id, sNo: 'Session ' + (i + 1), name: s.title || 'Session',
                    time: this._timeRange(s.startTime, s.endTime)
                }))
            };
        }).filter(d => d.sessions.length);
    }
    get feeSummaryToggleLabel() { return this.feeSummaryOpen ? 'Hide summary' : 'Show summary'; }
    _money(n) {
        return '₹' + Number(n || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }
    _fmtTime(hhmm) {
        if (!hhmm) return '';
        const [h, m] = String(hhmm).split(':').map(Number);
        const ampm = h < 12 ? 'am' : 'pm';
        const hr = (h % 12) || 12;
        return `${hr}:${String(m || 0).padStart(2, '0')}${ampm}`;
    }
    _timeRange(start, end) {
        const s = this._fmtTime(start), e = this._fmtTime(end);
        if (s && e) return `${s} to ${e}`;
        return s || e || '';
    }
    // Salesforce Time fields arrive as "HH:mm:ss.SSSZ" strings or milliseconds-since-midnight.
    _parseApexTime(v) {
        if (v == null || v === '') return '';
        if (typeof v === 'number') {
            const mins = Math.floor(v / 60000);
            return `${String(Math.floor(mins / 60)).padStart(2, '0')}:${String(mins % 60).padStart(2, '0')}`;
        }
        return String(v).slice(0, 5);   // "HH:mm:ss.SSSZ" → "HH:mm"
    }
    _fmtTime12(hhmm) {
        if (!hhmm) return '';
        const [h, m] = String(hhmm).split(':').map(Number);
        const ampm = h < 12 ? 'AM' : 'PM';
        const hr = (h % 12) || 12;
        return `${hr}:${String(m || 0).padStart(2, '0')} ${ampm}`;
    }
    _timeRange12(start, end) {
        const s = this._fmtTime12(start), e = this._fmtTime12(end);
        if (s && e) return `${s} – ${e}`;
        return s || e || '';
    }

    _loadFeeSessions() {
        if (!this.currentEventId) return;
        getEventSessions({ eventId: this.currentEventId })
            .then(rows => { this.feeSessions = (rows || []).map(r => ({ id: r.Id, name: r.Name, date: r.Start_Date__c, startTime: this._parseApexTime(r.Start_Time__c), endTime: this._parseApexTime(r.End_Time__c) })); })
            .catch(() => { this.feeSessions = []; });
    }
    selectPricingMode(e) { this.pricing = { ...this.pricing, mode: e.currentTarget.dataset.mode }; }
    toggleFeeSummary() { this.feeSummaryOpen = !this.feeSummaryOpen; }
    overallFeeInput(e) { this.pricing = { ...this.pricing, overallFee: e.target.value }; }
    overallFreeToggle(e) { this.pricing = { ...this.pricing, overallFree: e.target.checked }; }
    sessionFeeInput(e) {
        const id = e.target.dataset.id;
        const sf = { ...this.pricing.sessionFees };
        sf[id] = { ...(sf[id] || {}), fee: e.target.value };
        this.pricing = { ...this.pricing, sessionFees: sf };
    }
    sessionFreeToggle(e) {
        const id = e.target.dataset.id;
        const sf = { ...this.pricing.sessionFees };
        sf[id] = { ...(sf[id] || {}), free: e.target.checked };
        this.pricing = { ...this.pricing, sessionFees: sf };
    }
    async _persistStep5() {
        if (this.isOverall) {
            const fee = this.pricing.overallFree ? 0 : Math.round(Number(this.pricing.overallFee || 0));
            await updateFee({ isEventWise: true, eventId: this.currentEventId, eventFee: fee, isNoFee: this.pricing.overallFree, sessionsMap: [] });
        } else {
            const sessionsMap = this.feeSessions.map(s => {
                const f = this.pricing.sessionFees[s.id] || {};
                return { Id: s.id, Session_Fee__c: f.free ? 0 : Number(f.fee || 0), No_Fee__c: !!f.free };
            });
            await updateFee({ isEventWise: false, eventId: this.currentEventId, eventFee: null, isNoFee: false, sessionsMap });
        }
    }

    /* ================= Step 6 — Feedback Form ================= */
    get inFeedbackBuilder() { return !!this.activeFeedbackSessionId; }
    get isFeedbackBuilderActive() { return this.isStep6 && !!this.activeFeedbackSessionId; }
    // Feedback forms grouped by day, with sessions numbered per day (Session 1, 2, 3 …).
    get feedbackDays() {
        const byDate = {};
        const order = [];
        this.feeSessions.forEach(s => {
            const d = s.date || '';
            if (!byDate[d]) { byDate[d] = []; order.push(d); }
            byDate[d].push(s);
        });
        order.sort();
        return order.map(d => ({
            key: d || 'undated',
            label: d ? this._pretty(d) : '',
            sessions: byDate[d].map((s, i) => {
                const f = this.feedback[s.id];
                const count = f && f.questions ? f.questions.length : 0;
                const hasForm = !!(f && f.saved) || count > 0;   // a saved form counts even with no questions yet
                return {
                    id: s.id, sNo: 'Session ' + (i + 1), name: s.name,
                    hasForm,
                    btnLabel: hasForm ? 'Edit Form' : 'Setup Form',
                    badgeText: count > 0 ? (count + (count === 1 ? ' Question Added' : ' Questions Added')) : (hasForm ? 'Form Added' : 'No Feedback Form Added'),
                    badgeClass: hasForm ? 'hw-fbbadge hw-fbbadge--on' : 'hw-fbbadge'
                };
            })
        }));
    }
    get activeFeedbackName() {
        const s = this.feeSessions.find(x => x.id === this.activeFeedbackSessionId);
        return s ? s.name : '';
    }
    // Builder header: "Day N · Session X of Y", title, date · time, question count.
    get activeFeedbackMeta() {
        const id = this.activeFeedbackSessionId;
        if (!id) return {};
        const byDate = {};
        const order = [];
        this.feeSessions.forEach(s => { const d = s.date || ''; if (!byDate[d]) { byDate[d] = []; order.push(d); } byDate[d].push(s); });
        order.sort();
        for (let di = 0; di < order.length; di++) {
            const list = byDate[order[di]];
            const si = list.findIndex(s => s.id === id);
            if (si > -1) {
                const s = list[si];
                const count = ((this.feedback[id] && this.feedback[id].questions) || []).length;
                return {
                    dayLabel: 'Day ' + (di + 1),
                    sessionOfTotal: 'Session ' + (si + 1) + ' of ' + list.length,
                    title: s.name,
                    dateLabel: s.date ? this._pretty(s.date) : '',
                    timeLabel: this._timeRange12(s.startTime, s.endTime),
                    countLabel: count + ' Question(s) Added'
                };
            }
        }
        return {};
    }
    get activeFeedbackForm() { return this.feedback[this.activeFeedbackSessionId] || {}; }
    get triggerAutoChecked() { return (this.activeFeedbackForm.triggerType || 'auto') === 'auto'; }
    get triggerManualChecked() { return this.activeFeedbackForm.triggerType === 'manual'; }
    get triggerWhenOptions() {
        const sel = this.activeFeedbackForm.triggerWhen || '';
        return TRIGGER_WHEN_OPTIONS.map(o => ({ ...o, selected: o.value === sel }));
    }
    get questionTypeOptions() { return QUESTION_TYPES; }
    get activeQuestions() {
        return (this.activeFeedbackForm.questions || []).map((q, i) => {
            const opts = Array.isArray(q.options) ? q.options : [];
            return {
                ...q, number: i + 1,
                isMcq: q.type === 'Multiple choice',
                typeOptions: QUESTION_TYPES.map(t => ({ ...t, selected: t.value === q.type })),
                optionRows: opts.map((o, j) => ({ key: q.id + '-o' + j, idx: j, letter: String.fromCharCode(97 + j) + ')', value: o }))
            };
        });
    }

    _ensureFeedback(id) {
        if (!this.feedback[id]) {
            this.feedback = { ...this.feedback, [id]: { triggerType: 'auto', triggerWhen: '', endDate: '', endTime: '', questions: [] } };
        }
    }
    openFeedbackForm(e) {
        const id = e.currentTarget.dataset.id;
        // Snapshot the existing form so "Discard Changes" can revert (undefined = it didn't exist yet).
        const existing = this.feedback[id];
        this._feedbackSnapshot = existing ? JSON.parse(JSON.stringify(existing)) : undefined;
        this._ensureFeedback(id);
        this.activeFeedbackSessionId = id;
    }
    closeFeedbackForm() { this.activeFeedbackSessionId = null; this._feedbackSnapshot = undefined; }
    // Footer "Save Form": keep in-memory edits (persisted to the server when the step advances),
    // flash a "Feedback Form Saved" confirmation, then return to the list.
    saveFeedbackForm() {
        const id = this.activeFeedbackSessionId;
        if (id && this.feedback[id]) {
            this.feedback = { ...this.feedback, [id]: { ...this.feedback[id], saved: true } };
        }
        this._feedbackSnapshot = undefined;
        this.activeFeedbackSessionId = null;
        this.showFeedbackSavedToast = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showFeedbackSavedToast = false; }, 1800);
    }
    // Footer "Discard Changes": roll back to the snapshot taken when the form was opened.
    discardFeedbackForm() {
        const id = this.activeFeedbackSessionId;
        if (id) {
            const next = { ...this.feedback };
            if (this._feedbackSnapshot === undefined) delete next[id];
            else next[id] = this._feedbackSnapshot;
            this.feedback = next;
        }
        this._feedbackSnapshot = undefined;
        this.activeFeedbackSessionId = null;
    }
    _updateForm(mut) {
        const id = this.activeFeedbackSessionId;
        this.feedback = { ...this.feedback, [id]: mut({ ...this.feedback[id] }) };
    }
    setTrigger(e) { const v = e.target.value; this._updateForm(f => { f.triggerType = v; return f; }); }
    setTriggerWhen(e) { const v = e.target.value; this._updateForm(f => { f.triggerWhen = v; return f; }); }
    feedbackDateField(e) { const fld = e.target.dataset.field, v = e.target.value; this._updateForm(f => { f[fld] = v; return f; }); }
    addQuestion() {
        this._qSeq += 1;
        this._updateForm(f => {
            f.questions = (f.questions || []).concat([{ id: 'q-' + this._qSeq, type: 'Multiple choice', text: '', required: false, options: [''] }]);
            return f;
        });
    }
    questionField(e) {
        const id = e.target.dataset.id, fld = e.target.dataset.field, v = e.target.value;
        this._updateForm(f => {
            f.questions = f.questions.map(q => {
                if (q.id !== id) return q;
                const next = { ...q, [fld]: v };
                // Switching to Multiple choice with no options yet seeds an empty first option.
                if (fld === 'type' && v === 'Multiple choice' && !(Array.isArray(q.options) && q.options.length)) next.options = [''];
                return next;
            });
            return f;
        });
    }
    addOption(e) {
        const id = e.currentTarget.dataset.id;
        this._updateForm(f => { f.questions = f.questions.map(q => (q.id === id ? { ...q, options: [...(q.options || []), ''] } : q)); return f; });
    }
    removeOption(e) {
        const id = e.currentTarget.dataset.id, idx = parseInt(e.currentTarget.dataset.idx, 10);
        this._updateForm(f => { f.questions = f.questions.map(q => (q.id === id ? { ...q, options: (q.options || []).filter((o, j) => j !== idx) } : q)); return f; });
    }
    optionInput(e) {
        const id = e.target.dataset.id, idx = parseInt(e.target.dataset.idx, 10), v = e.target.value;
        this._updateForm(f => { f.questions = f.questions.map(q => (q.id === id ? { ...q, options: (q.options || []).map((o, j) => (j === idx ? v : o)) } : q)); return f; });
    }
    toggleRequired(e) {
        const id = e.target.dataset.id, v = e.target.checked;
        this._updateForm(f => { f.questions = f.questions.map(q => (q.id === id ? { ...q, required: v } : q)); return f; });
    }
    removeQuestion(e) {
        const id = e.currentTarget.dataset.id;
        this._updateForm(f => { f.questions = f.questions.filter(q => q.id !== id); return f; });
    }
    async _persistStep6() {
        for (const sid of Object.keys(this.feedback)) {
            const f = this.feedback[sid];
            if (!f) continue;
            if (f.questions && f.questions.length) {
                const questions = f.questions.map((q, i) => ({
                    Question_Label__c: q.text || ('Question ' + (i + 1)),
                    Question_Type__c: q.type || 'Multiple choice',
                    Is_Required__c: !!q.required,
                    Order__c: i + 1,
                    MCQ_Options__c: Array.isArray(q.options) ? (q.options.filter(o => o && o.trim()).join('\n') || null) : (q.options || null)
                }));
                // eslint-disable-next-line no-await-in-loop
                await saveQuestionnaireForSession({ sessionId: sid, questionnaire: { Section_Name__c: this._sessionName(sid) }, questions }).catch(() => {});
            }
            // eslint-disable-next-line no-await-in-loop
            await saveFeedbackTriggerSettings({ sessionId: sid, triggerType: f.triggerType || 'auto', triggerWhen: f.triggerWhen || '', endDate: f.endDate || '', endTime: f.endTime || '' }).catch(() => {});
        }
    }
    _sessionName(id) { const s = this.feeSessions.find(x => x.id === id); return s ? s.name : 'Session'; }

    /* ================= Step 7 — Summary ================= */
    get summaryDateText() {
        if (!this.selectedDates.length) return '—';
        return this.selectedDatePills.map(p => p.label).join(', ');
    }
    get summaryGuests() { return this.ev.canBringGuests === 'yes' ? ('Yes — up to ' + this.ev.maxGuests + ' guest(s)') : 'No'; }
    get summarySessionCount() {
        let n = 0; this.selectedDates.forEach(d => { n += (this.sessionsByDate[d] || []).length; }); return n;
    }
    get summaryPricing() {
        if (this.isOverall) return 'Overall · ' + this.totalEventCostDisplay;
        return 'Session-wise · ' + this.totalEventCostDisplay;
    }
    get summaryAudience() {
        const a = this.audience;
        if (!a) return 'Not set';
        const parts = [];
        if (a.category) parts.push(a.category);
        const groups = (a.groupIds || a.groups || []);
        if (groups.length) parts.push(groups.length + ' group(s)');
        const ind = (a.individualIds || a.individuals || []);
        if (ind.length) parts.push(ind.length + ' individual(s)');
        return parts.length ? parts.join(' • ') : 'All eligible';
    }
    get summaryFeedback() {
        const n = Object.keys(this.feedback).filter(k => {
            const f = this.feedback[k];
            return f && (f.saved || (f.questions && f.questions.length));
        }).length;
        return n ? (n + ' session feedback form(s) configured') : 'No feedback forms';
    }
    get summarySurvey() {
        if (!this.survey.customSurvey) return 'Custom survey off';
        const n = (this.survey.questions || []).length;
        return n ? (n + ' preference question(s)') : 'No questions added';
    }
    get surveyQuestionCountLabel() {
        if (!this.survey.customSurvey) return 'Off';
        const n = (this.survey.questions || []).length;
        return n + (n === 1 ? ' Question' : ' Questions');
    }
    get hasSummaryBrochure() { return !!this.ev.brochureName; }
    get brochureDownloadUrl() {
        return this.ev.brochureBase64 ? `data:${this.ev.brochureType || 'application/pdf'};base64,${this.ev.brochureBase64}` : '';
    }
    // Target Audience cards: each saved group/audience with its name + chips.
    get summaryAudienceGroups() {
        const a = this.audience || {};
        const out = [];
        (a.groups || []).forEach((g, i) => {
            const chips = [];
            (a.roles || []).forEach((r, ri) => chips.push({ key: 'r' + i + ri, label: r, cls: 'hw-chip hw-chip--primary' }));
            const members = g.memberCount != null ? (g.memberCount + ' Members') : (g.membersLabel || '');
            if (members) chips.push({ key: 'm' + i, label: members, cls: 'hw-chip' });
            out.push({ key: g.id || 'g' + i, name: g.name || ('Group ' + (i + 1)), chips });
        });
        (a.savedAudiences || []).forEach((s, i) => {
            const chips = [];
            const members = s.memberCount != null ? (s.memberCount + ' Members') : '';
            if (members) chips.push({ key: 'sm' + i, label: members, cls: 'hw-chip' });
            out.push({ key: s.id || 's' + i, name: s.name || ('Audience ' + (i + 1)), chips });
        });
        return out;
    }
    get hasSummaryAudience() { return this.summaryAudienceGroups.length > 0; }
    // Combined Session Details table: day → session, price and feedback question count.
    get summarySessionDays() {
        const byDate = {};
        const order = [];
        this.feeSessions.forEach(s => { const d = s.date || ''; if (!byDate[d]) { byDate[d] = []; order.push(d); } byDate[d].push(s); });
        order.sort();
        return order.map(d => ({
            key: d || 'undated',
            label: d ? this._pretty(d) : '',
            sessions: byDate[d].map((s, i) => {
                const fee = this.pricing.sessionFees[s.id] || {};
                const priceDisplay = (fee.free || !fee.fee) ? '₹-' : this._money(Number(fee.fee));
                const fb = this.feedback[s.id];
                const qc = (fb && fb.questions) ? fb.questions.length : 0;
                const feedbackDisplay = qc ? (qc + ' Questions') : ((fb && fb.saved) ? 'Form Added' : '-');
                return { id: s.id, sNo: 'Session ' + (i + 1), name: s.name, priceDisplay, feedbackDisplay };
            })
        }));
    }
    get hasSummarySessions() { return this.feeSessions.length > 0; }
    jumpToStep(e) {
        const n = parseInt(e.currentTarget.dataset.step, 10);
        if (n >= 1 && n <= 7) {
            this.audienceExpanded = false;
            this.step = n;
            if (n === 3) this._ensureSchedule();
            if (n === 5 || n === 6) this._loadFeeSessions();   // Fee · Feedback need session list
        }
    }

    /* ================= final submit ================= */
    async _submitForApproval() {
        const wrapper = this._buildEventWrapper('Pending Approval');
        await saveEvent({ eventData: JSON.stringify(wrapper), constituentRoleId: this.roleId });
        // Speaker invites: sessions with "Share an Email Invite" checked + a speaker email on file.
        const invites = this._collectSpeakerInvites();
        if (invites.length) {
            // Don't block submission if the email send fails (e.g. sandbox email deliverability off).
            try { await sendSpeakerInvites({ invitesJson: JSON.stringify(invites) }); } catch (e) { /* noop */ }
        }
    }
    _collectSpeakerInvites() {
        const invites = [];
        const eventName = this.ev.title || 'our event';
        Object.keys(this.sessionsByDate || {}).forEach(iso => {
            (this.sessionsByDate[iso] || []).forEach(s => {
                if (!s.shareEmailInvite) return;
                (s.speakers || []).forEach(sp => {
                    const email = (sp.email || '').trim();
                    if (!email) return;
                    invites.push({
                        name: sp.name || '',
                        email,
                        eventName,
                        eventDate: this._pretty(iso),
                        sessionTitle: s.title || 'Session'
                    });
                });
            });
        });
        return invites;
    }
    closeSuccess() {
        this.showSuccess = false;
        this.dispatchEvent(new CustomEvent('close', { detail: { eventId: this.currentEventId, submitted: true } }));
    }

    /* ================= save orchestration (Step 1) ================= */
    _buildEventWrapper(status) {
        return {
            Id: this.currentEventId || null,
            eventTitle: this.ev.title,
            eventTypes: this.ev.category || null,
            eventStatus: status,
            description: this.ev.description || null,
            agenda: this.ev.agenda || null,
            startDate: this.selectedDates[0] || null,
            endDate: this.selectedDates[this.selectedDates.length - 1] || null,
            maximumNumberOfParticipants: this.ev.maxParticipants ? Number(this.ev.maxParticipants) : null,
            eventLanguages: this.ev.language || null,
            canAlumniBringGuests: this.ev.canBringGuests === 'yes',
            guestCount: this.ev.canBringGuests === 'yes' ? Number(this.ev.maxGuests) : 0,
            currentStep: this.step,
            isPortal: true
        };
    }

    async _persistStep1(status) {
        const wrapper = this._buildEventWrapper(status);
        const eventId = await saveEvent({ eventData: JSON.stringify(wrapper), constituentRoleId: this.roleId });
        this.currentEventId = eventId;
        // Attach cover + brochure to the saved event record.
        if (this.ev.coverBase64) {
            await uploadFileToRecord({ recordId: eventId, fileName: this.ev.coverName, base64Data: this.ev.coverBase64, contentType: this.ev.coverType })
                .catch(() => {});
        }
        if (this.ev.brochureBase64) {
            await uploadFileToRecord({ recordId: eventId, fileName: this.ev.brochureName, base64Data: this.ev.brochureBase64, contentType: this.ev.brochureType })
                .catch(() => {});
        }
        return eventId;
    }

    /* ================= footer actions ================= */
    async handlePrimary() {
        if (this.step === 1) {
            const miss = this._validateStep1();
            if (miss.length) { this.errorMsg = 'Please fill the required field(s): ' + miss.join(', ') + '.'; return; }
            this.saving = true;
            try {
                await this._persistStep1('In Progress');
                this.errorMsg = '';
                this.step = 2;
            } catch (err) {
                this.errorMsg = (err && err.body && err.body.message) || 'Could not save the event. Please try again.';
            } finally { this.saving = false; }
            return;
        }
        if (this.step === 2) {
            this.saving = true;
            try {
                await this._persistStep2();
                this.errorMsg = '';
                this._ensureSchedule();
                this.step = 3;
            } catch (err) {
                this.errorMsg = (err && err.body && err.body.message) || 'Could not save the audience.';
            } finally { this.saving = false; }
            return;
        }
        if (this.step === 3) {
            const err3 = this._validateStep3();
            if (err3) { this.errorMsg = err3; return; }
            this.saving = true;
            try {
                await this._persistStep3();
                this.errorMsg = '';
                this.step = 4;   // → Pre Event Surveys
            } catch (err) {
                this.errorMsg = (err && err.body && err.body.message) || 'Could not save the schedule.';
            } finally { this.saving = false; }
            return;
        }
        if (this.step === 4) {   // Pre Event Surveys
            this.saving = true;
            try {
                await this._persistStep4();
                this.errorMsg = '';
                this._loadFeeSessions();   // Fee Setup is next
                this.step = 5;
            } catch (err) {
                this.errorMsg = (err && err.body && err.body.message) || 'Could not save the survey.';
            } finally { this.saving = false; }
            return;
        }
        if (this.step === 5) {   // Fee Setup
            this.saving = true;
            try {
                await this._persistStep5();
                this.errorMsg = '';
                if (!this.feeSessions.length) this._loadFeeSessions();
                this.step = 6;
            } catch (err) {
                this.errorMsg = (err && err.body && err.body.message) || 'Could not save the pricing.';
            } finally { this.saving = false; }
            return;
        }
        if (this.step === 6) {   // Feedback Form
            this.activeFeedbackSessionId = null;
            this.saving = true;
            try {
                await this._persistStep6();
                this.errorMsg = '';
                this.step = 7;
            } catch (err) {
                this.errorMsg = (err && err.body && err.body.message) || 'Could not save the feedback forms.';
            } finally { this.saving = false; }
            return;
        }
        if (this.step === 7) {   // Summary → submit
            this.saving = true;
            try {
                await this._submitForApproval();
                this.errorMsg = '';
                this.showSuccess = true;
            } catch (err) {
                this.errorMsg = (err && err.body && err.body.message) || 'Could not submit the event for approval.';
            } finally { this.saving = false; }
            return;
        }
    }

    async handleSaveDraft() {
        if (this.step === 1 && (!this.ev.title || !this.ev.title.trim())) {
            this.errorMsg = 'Add an Event Title before saving a draft.';
            return;
        }
        this.saving = true;
        try {
            if (this.step >= 1) await this._persistStep1('In Progress');
            this.dispatchEvent(new CustomEvent('savedraft', { detail: { eventId: this.currentEventId } }));
            this.errorMsg = '';
        } catch (err) {
            this.errorMsg = (err && err.body && err.body.message) || 'Could not save draft.';
        } finally { this.saving = false; }
    }

    handleBack() {
        this.errorMsg = '';
        this.audienceExpanded = false;
        if (this.step > 1) this.step -= 1;
        if (this.step === 3) this._ensureSchedule();
        if (this.step === 5 || this.step === 6) this._loadFeeSessions();   // Fee · Feedback
    }
    handleCancel() { this.dispatchEvent(new CustomEvent('close')); }
}