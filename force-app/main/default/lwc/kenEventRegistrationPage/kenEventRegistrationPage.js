import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEventDetails from '@salesforce/apex/KenPortalEventController.getEventDetails';
import getEventSchedules from '@salesforce/apex/KenPortalEventController.getEventSchedules';
import searchAudienceGroups from '@salesforce/apex/KenAudienceEngineService.searchAudienceGroups';
import getCurrentParticipantDetails from '@salesforce/apex/KenPortalEventController.getCurrentParticipantDetails';
import saveRegistrations from '@salesforce/apex/KenPortalEventController.saveRegistrations';
import saveEventRegistrations from '@salesforce/apex/KenPortalEventController.saveEventRegistrations';
import getQuestionnaireByEventId from '@salesforce/apex/KenEventFormController.getQuestionnaireByEventId';
import { getPortalConfigs } from 'c/kenThemeConfig';

export default class KenEventRegistrationPage extends NavigationMixin(LightningElement) {

    // When used as modal inside kenEventDetails, parent passes recordId directly
    // and embeddedModal=true so close navigates via event instead of page nav
    @api embeddedModal = false;
    _apiRecordId = null;
    @api get recordId() { return this._apiRecordId; }
    set recordId(val) {
        this._apiRecordId = val;
        if (val && !this._routeRecordId) {
            this._initWithRecordId(val);
        }
    }

    _routeRecordId = null;
    @track eventData;
    @track isLoadingEvent = true;

    @track currentStep = 1;
    @track registrationType = 'myself';
    @track participants = [];
    @track guestName = '';
    @track guestEmail = '';
    @track guestEmailError = '';
    @track guestPhone = '';
    @track searchQuery = '';
    @track groupSearchTerm = '';
    @track currentPage = 1;
    @track groups = [];
    @track sessions = [];
    @track dateGroups = [];
    @track selectedSessionIds = new Set();
    @track isLoading = false;
    @track questionnaireId = null;

    @track constituentRoleId = null;
    // When the org has Disable_Event_Fee__c enabled, all fee/payment UI is hidden.
    @track feeDisabled = false;
    @track _refreshTick = 0;
    pageSize = 5;
    _participantIdCounter = 1;

    get _recordId() {
        return this._routeRecordId || this._apiRecordId;
    }

    connectedCallback() {
        // Re-render when the user returns from the survey form (browser back / bfcache)
        // so a just-submitted participant's "Fill" flips to "Submitted".
        this._boundRefresh = () => { this._refreshTick++; };
        window.addEventListener('focus', this._boundRefresh);
        window.addEventListener('pageshow', this._boundRefresh);

        getPortalConfigs()
            .then(cfg => { this.feeDisabled = cfg?.disableEventFee === true; })
            .catch(() => {});
    }

    disconnectedCallback() {
        if (this._boundRefresh) {
            window.removeEventListener('focus', this._boundRefresh);
            window.removeEventListener('pageshow', this._boundRefresh);
        }
    }

    _isSurveySubmitted(participantId) {
        try {
            const arr = JSON.parse(sessionStorage.getItem('kenFbSubmitted:' + this._recordId) || '[]');
            return arr.includes(participantId) || arr.includes('__self__');
        } catch (e) {
            return false;
        }
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (pageRef?.state?.recordId) {
            this._routeRecordId = pageRef.state.recordId;
            this._initWithRecordId(this._routeRecordId);
        }
    }

    @wire(getEventDetails, { recordId: '$_recordId' })
    wiredEvent({ data, error }) {
        if (data) {
            this.eventData = data;
            this.isLoadingEvent = false;
            this._loadCurrentUser();
            this._loadGroups();
            this._loadQuestionnaire();
        } else if (error) {
            this.isLoadingEvent = false;
        }
    }

    _initWithRecordId(id) {
        if (!id) return;
        this._loadCurrentUser();
        this._loadGroups();
    }

    _loadQuestionnaire() {
        const rid = this._recordId;
        if (!rid) return;
        getQuestionnaireByEventId({ eventId: rid })
            .then(result => {
                // Apex returns an SObject — the id field is `Id` (capital), not `id`.
                const qId = result && (result.Id || result.id);
                if (qId) {
                    this.questionnaireId = qId;
                }
            })
            .catch(() => {});
    }

    _loadCurrentUser() {
        try {
            this.constituentRoleId = localStorage.getItem('ConstituentRoleId') || localStorage.getItem('constituentRoleId') || sessionStorage.getItem('ConstituentRoleId') || sessionStorage.getItem('constituentRoleId');
        } catch (e) {
            this.constituentRoleId = null;
        }

        // If the user is coming back from taking the survey, restore their
        // in-progress participants/guests/group instead of resetting.
        if (this._restoreRegistrationDraft()) {
            return;
        }

        if (!this.constituentRoleId) {
            this.participants = [{
                id: 'myself_0',
                name: 'Me',
                email: '',
                phone: '',
                type: 'myself',
                typeLabel: 'Myself',
                typeClass: 'type-badge type-myself',
                meals: false,
                dietaryPref: '',
                selected: true,
                canDelete: false,
                dietaryOptions: this._buildDietaryOptions('')
            }];
            return;
        }
        getCurrentParticipantDetails({ constituentRoleId: this.constituentRoleId })
            .then(details => {
                this.participants = [{
                    id: 'myself_0',
                    name: details.name || 'Me',
                    email: details.email || '',
                    phone: details.phone || '',
                    type: 'myself',
                    typeLabel: 'Myself',
                    typeClass: 'type-badge type-myself',
                    meals: false,
                    dietaryPref: '',
                    selected: true,
                    canDelete: false,
                    dietaryOptions: this._buildDietaryOptions('')
                }];
            })
            .catch(() => {
                this.participants = [{
                    id: 'myself_0',
                    name: 'Me',
                    email: '',
                    phone: '',
                    type: 'myself',
                    typeLabel: 'Myself',
                    typeClass: 'type-badge type-myself',
                    meals: false,
                    dietaryPref: '',
                    selected: true,
                    canDelete: false,
                    dietaryOptions: this._buildDietaryOptions('')
                }];
            });
    }

    _loadGroups() {
        searchAudienceGroups({ searchTerm: '', limitSize: 100 })
            .then(result => {
                this.groups = (result || []).map(g => ({
                    id: g.id || g.Id,
                    name: g.name || g.Name,
                    memberCount: g.memberCount || 0,
                    membersLabel: `${g.memberCount || 0} Members`,
                    selected: false
                }));
            })
            .catch(() => {
                this.groups = [];
            });
    }

    _buildDietaryOptions(currentValue) {
        const raw = (this.eventData && this.eventData.dietaryPreferences) ? this.eventData.dietaryPreferences : '';
        // Dietary Preferences is a multi-select picklist (semicolon-separated values,
        // e.g. "Vegan;Eggetarian"); also tolerate commas. Split into one option each.
        return raw.split(/[;,]/).filter(o => o.trim()).map(o => ({
            value: o.trim(),
            label: o.trim(),
            selected: o.trim() === currentValue
        }));
    }

    @wire(getEventSchedules, { eventId: '$_recordId', constituentRoleId: '$constituentRoleId' })
    wiredSchedules({ data, error }) {
        if (data) {
            this._processSchedules(data);
        } else if (error) {
            this.sessions = [];
            this.dateGroups = [];
        }
    }

    _processSchedules(data) {
        const sorted = [...data].sort((a, b) => {
            const dateA = a.sessionDate || '';
            const dateB = b.sessionDate || '';
            if (dateA !== dateB) return dateA < dateB ? -1 : 1;
            return (a.startTime || 0) - (b.startTime || 0);
        });

        this.sessions = sorted.map(s => ({
            id: s.id || s.Id,
            title: s.title || s.Name || 'Session',
            sessionDate: s.sessionDate ? this._formatDateStr(s.sessionDate) : null,
            sessionDateRaw: s.sessionDate,
            startTime: s.startTime != null ? this._msToTime(s.startTime) : null,
            endTime: s.endTime != null ? this._msToTime(s.endTime) : null,
            price: s.price ? Number(s.price) : 0,
            isRegistered: !!s.isRegistered,
            checked: !s.isRegistered,
            disabled: !!s.isRegistered
        }));

        const newSelected = new Set();
        this.sessions.forEach(s => {
            if (s.checked) newSelected.add(s.id);
        });
        this.selectedSessionIds = newSelected;
        this._buildDateGroups();
    }

    _buildDateGroups() {
        const map = new Map();
        this.sessions.filter(s => !s.isRegistered).forEach(s => {
            const key = s.sessionDate || 'Unknown';
            if (!map.has(key)) {
                map.set(key, { dateKey: key, displayDate: key, sessions: [] });
            }
            map.get(key).sessions.push({ ...s });
        });

        this.dateGroups = [...map.values()].map(dg => ({
            ...dg,
            totalPrice: dg.sessions.reduce((sum, s) => sum + (s.price || 0), 0),
            allSelected: dg.sessions.every(s => this.selectedSessionIds.has(s.id))
        }));
    }

    _msToTime(ms) {
        if (ms == null) return '';
        const totalMinutes = Math.floor(ms / 60000);
        const hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;
        const ampm = hours >= 12 ? 'PM' : 'AM';
        const displayHour = hours % 12 || 12;
        return `${displayHour}:${minutes.toString().padStart(2, '0')} ${ampm}`;
    }

    _formatDateStr(dateStr) {
        if (!dateStr) return '';
        try {
            const d = new Date(dateStr + 'T00:00:00');
            return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
        } catch (e) {
            return dateStr;
        }
    }

    // -- Step getters --
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep1Complete() { return this.currentStep > 1; }
    get isStep2Complete() { return this.currentStep > 2; }
    get showBackButton() { return this.currentStep > 1; }
    get showSessionFooterInfo() { return this.currentStep >= 2; }

    get progressStyle() {
        const pct = this.currentStep === 1 ? 33.33 : this.currentStep === 2 ? 66.66 : 100;
        return `width: ${pct}%`;
    }

    get step1CircleClass() {
        if (this.isStep1Complete) return 'step-circle done';
        if (this.currentStep === 1) return 'step-circle active';
        return 'step-circle';
    }
    get step2CircleClass() {
        if (this.isStep2Complete) return 'step-circle done';
        if (this.currentStep === 2) return 'step-circle active';
        return 'step-circle';
    }
    get step3CircleClass() {
        return this.currentStep === 3 ? 'step-circle active' : 'step-circle';
    }
    get step1TextClass() {
        if (this.isStep1Complete) return 'step-text done';
        return this.currentStep === 1 ? 'step-text active' : 'step-text';
    }
    get step2TextClass() {
        if (this.isStep2Complete) return 'step-text done';
        return this.currentStep === 2 ? 'step-text active' : 'step-text';
    }
    get step3TextClass() {
        return this.currentStep === 3 ? 'step-text active' : 'step-text';
    }
    get connector12Class() {
        return this.currentStep > 1 ? 'step-connector done' : 'step-connector';
    }
    get connector23Class() {
        return this.currentStep > 2 ? 'step-connector done' : 'step-connector';
    }

    // -- Event data getters --
    get eventTitle() { return this.eventData ? this.eventData.name || this.eventData.title || '' : ''; }
    get eventDateRange() { return this.eventData ? this.eventData.dateRange || this.eventData.startDate || '' : ''; }
    get eventLocation() { return this.eventData ? this.eventData.location || this.eventData.venueName || '' : ''; }
    get eventLanguage() { return this.eventData ? this.eventData.language || '' : ''; }
    get formattedLanguage() {
        const lang = this.eventLanguage;
        if (!lang) return '';
        return lang.split(';').map(l => l.trim()).filter(l => l).join(', ');
    }

    // -- Mode getters --
    get isMyselfMode() { return this.registrationType === 'myself'; }
    get isBulkMode() { return this.registrationType === 'bulk'; }
    get myselfBtnClass() { return this.isMyselfMode ? 'mode-btn active' : 'mode-btn'; }
    get bulkBtnClass() { return this.isBulkMode ? 'mode-btn active' : 'mode-btn'; }

    // -- Meal/dietary getters --
    get showMealsColumn() { return !!(this.eventData && this.eventData.offerMeals); }
    get showDietaryColumn() { return !!(this.eventData && this.eventData.collectDietary); }
    get hasSurvey() { return !!this.questionnaireId; }
    // Master switch for all fee/payment UI on this page.
    get showFees() { return !this.feeDisabled; }
    get showFeeLabel() { return this.showFees && !!(this.eventData && !this.eventData.noFee && this.sessions.length > 0); }
    get sessionPriceLabel() {
        const priced = this.sessions.find(s => s.price > 0);
        return priced ? priced.price.toLocaleString('en-IN') : '0';
    }

    // -- Participants getters --
    // A group counts as all its members, individuals (myself/guest) count as 1 each.
    get participantCount() {
        return this.participants.reduce((sum, p) => {
            if (p.type === 'group') return sum + (Number(p.memberCount) || 0);
            return sum + 1;
        }, 0);
    }
    get participantRowCount() { return this.participants.length; }
    get hasParticipants() { return this.participants.length > 0; }
    get hasGroups() { return this.groups.length > 0; }

    get filteredGroups() {
        const q = (this.groupSearchTerm || '').trim().toLowerCase();
        if (!q) return this.groups;
        return this.groups.filter(g => (g.name || '').toLowerCase().includes(q));
    }
    get hasFilteredGroups() { return this.filteredGroups.length > 0; }

    handleGroupSearch(e) {
        this.groupSearchTerm = e.target.value || '';
    }

    get filteredParticipants() {
        if (!this.searchQuery) return this.participants;
        const q = this.searchQuery.toLowerCase();
        return this.participants.filter(p =>
            (p.name || '').toLowerCase().includes(q) ||
            (p.email || '').toLowerCase().includes(q)
        );
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.filteredParticipants.length / this.pageSize));
    }

    get pagedParticipants() {
        const start = (this.currentPage - 1) * this.pageSize;
        return this.filteredParticipants.slice(start, start + this.pageSize).map(p => ({
            ...p,
            dietaryOptions: this._buildDietaryOptions(p.dietaryPref || ''),
            // Dietary preference is only relevant when the participant is having meals.
            dietaryDisabled: !p.meals,
            // Has this participant's survey been submitted? (drives Fill -> Submitted)
            surveySubmitted: this._isSurveySubmitted(p.id)
        }));
    }

    get showPagination() { return this.filteredParticipants.length > this.pageSize; }
    get isPrevDisabled() { return this.currentPage <= 1; }
    get isNextDisabled() { return this.currentPage >= this.totalPages; }

    get pageNumbers() {
        const pages = [];
        for (let i = 1; i <= this.totalPages; i++) {
            pages.push({
                label: String(i),
                value: i,
                cls: i === this.currentPage ? 'page-num active' : 'page-num'
            });
        }
        return pages;
    }

    get allSelected() {
        const paged = this.pagedParticipants;
        return paged.length > 0 && paged.every(p => p.selected);
    }

    // -- Session getters --
    get hasDateGroups() { return this.dateGroups.length > 0; }
    get selectedSessionCount() { return this.selectedSessionIds.size; }

    get selectedSessions() {
        return this.sessions.filter(s => this.selectedSessionIds.has(s.id));
    }

    get selectedSessionsByDate() {
        const map = new Map();
        this.selectedSessions.forEach(s => {
            const key = s.sessionDate || 'Unknown';
            if (!map.has(key)) {
                map.set(key, { dateKey: key, displayDate: key, sessions: [] });
            }
            map.get(key).sessions.push(s);
        });
        return [...map.values()];
    }

    get hasSelectedSessions() { return this.selectedSessions.length > 0; }

    get totalAmount() {
        const sessionSum = this.selectedSessions.reduce((sum, s) => sum + (s.price || 0), 0);
        return sessionSum * this.participantCount + this.mealFeeTotal;
    }

    get totalAmountFormatted() {
        return this.totalAmount.toLocaleString('en-IN');
    }

    // ---- Paid meals add-on (only when the host marked meals as paid) ----
    get mealFeePerHead() {
        if (!this.eventData || !this.eventData.makeMealsPaid) return 0;
        return Number(this.eventData.mealFee) || 0;
    }
    // Heads opting for meals — group participants count by their member count, mirroring participantCount.
    get mealHeadCount() {
        return this.participants.reduce((sum, p) => {
            if (!p.meals) return sum;
            if (p.type === 'group') return sum + (Number(p.memberCount) || 0);
            return sum + 1;
        }, 0);
    }
    get mealFeeTotal() {
        return this.mealFeePerHead * this.mealHeadCount;
    }
    get mealFeeTotalFormatted() {
        return this.mealFeeTotal.toLocaleString('en-IN');
    }
    get mealFeePerHeadFormatted() {
        return this.mealFeePerHead.toLocaleString('en-IN');
    }
    get showMealFeeRow() {
        return this.mealFeePerHead > 0 && this.mealHeadCount > 0;
    }

    get sessionSubtotal() {
        return this.selectedSessions.reduce((sum, s) => sum + (s.price || 0), 0).toLocaleString('en-IN');
    }

    // Per-participant session cost as a raw number (for the participant multiplier).
    get sessionSubtotalRaw() {
        return this.selectedSessions.reduce((sum, s) => sum + (s.price || 0), 0);
    }

    // Full session cost across all participants — matches what feeds the Total Payable.
    get sessionGrandTotal() {
        return this.sessionSubtotalRaw * this.participantCount;
    }
    get sessionGrandTotalFormatted() {
        return this.sessionGrandTotal.toLocaleString('en-IN');
    }

    get pricePerSession() {
        if (this.selectedSessions.length === 0) return '0';
        const total = this.selectedSessions.reduce((sum, s) => sum + (s.price || 0), 0);
        return (total / this.selectedSessions.length).toLocaleString('en-IN');
    }

    get mealsAddedText() {
        const hasMeals = this.participants.some(p => p.meals);
        return hasMeals ? 'Yes (Included for all)' : 'No';
    }

    // -- Handlers: mode --
    handleMyselfMode() { this.registrationType = 'myself'; }
    handleBulkMode() { this.registrationType = 'bulk'; }

    // -- Handlers: guest form --
    handleGuestNameChange(e) { this.guestName = e.target.value; }
    handleGuestEmailChange(e) {
        this.guestEmail = e.target.value;
        const v = (this.guestEmail || '').trim();
        const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        this.guestEmailError = (v && !emailRe.test(v)) ? 'Please enter a valid email address' : '';
    }
    handleGuestPhoneChange(e) {
        this.guestPhone = e.detail?.e164 || e.detail?.national || e.target?.value || '';
    }

    get maxGuests() {
        const n = this.eventData && this.eventData.guestCount != null ? Number(this.eventData.guestCount) : 0;
        return n > 0 ? n : 5;
    }

    get guestLimitLabel() {
        return `Upto ${this.maxGuests} guests can be added`;
    }

    get canAddGuests() {
        return !this.eventData || this.eventData.canBringGuests !== false;
    }

    handleAddGuest() {
        if (!this.canAddGuests) {
            this._showToast('Error', 'Guests are not allowed for this event.', 'error');
            return;
        }
        if (!this.guestName) {
            this._showToast('Error', 'Name is required.', 'error');
            return;
        }
        const emailVal = (this.guestEmail || '').trim();
        const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailVal) {
            this.guestEmailError = 'Email is required';
            return;
        }
        if (!emailRe.test(emailVal)) {
            this.guestEmailError = 'Please enter a valid email address';
            return;
        }
        this.guestEmailError = '';
        const guestCount = this.participants.filter(p => p.type === 'guest').length;
        if (guestCount >= this.maxGuests) {
            this._showToast('Error', `Maximum ${this.maxGuests} guests can be added.`, 'error');
            return;
        }
        const id = `guest_${++this._participantIdCounter}`;
        this.participants = [...this.participants, {
            id,
            name: this.guestName,
            email: this.guestEmail,
            phone: this.guestPhone,
            type: 'guest',
            typeLabel: 'Guest',
            typeClass: 'type-badge type-guest',
            meals: false,
            dietaryPref: '',
            selected: true,
            canDelete: true,
            dietaryOptions: this._buildDietaryOptions('')
        }];
        this.guestName = '';
        this.guestEmail = '';
        this.guestEmailError = '';
        this.guestPhone = '';
        this._saveRegistrationDraft();
    }

    // -- Handlers: groups --
    stopPropagation(e) { e.stopPropagation(); }

    handleGroupRowClick(e) {
        const id = e.currentTarget.dataset.id;
        this._toggleGroup(id);
    }

    handleGroupToggle(e) {
        e.stopPropagation();
        const id = e.target.dataset.id;
        this._toggleGroup(id);
    }

    _toggleGroup(id) {
        this.groups = this.groups.map(g => {
            if (g.id === id) {
                const newSelected = !g.selected;
                if (newSelected) {
                    const exists = this.participants.find(p => p.id === `group_${id}`);
                    if (!exists) {
                        this.participants = [...this.participants, {
                            id: `group_${id}`,
                            groupId: id,
                            memberCount: g.memberCount || 0,
                            name: g.name,
                            email: '',
                            phone: `${g.memberCount || 0} members`,
                            type: 'group',
                            typeLabel: 'Group',
                            typeClass: 'type-badge type-group',
                            meals: false,
                            dietaryPref: '',
                            selected: true,
                            canDelete: true,
                            dietaryOptions: this._buildDietaryOptions('')
                        }];
                    }
                } else {
                    this.participants = this.participants.filter(p => p.id !== `group_${id}`);
                }
                return { ...g, selected: newSelected };
            }
            return g;
        });
        this._saveRegistrationDraft();
    }

    // -- Handlers: participants table --
    handleDeleteParticipant(e) {
        const id = e.currentTarget.dataset.id;
        this.participants = this.participants.filter(p => p.id !== id);
        this.groups = this.groups.map(g => {
            if (`group_${g.id}` === id) return { ...g, selected: false };
            return g;
        });
        this._saveRegistrationDraft();
    }

    // ---- Registration draft (persist on the spot; restore after survey return) ----
    get _draftKey() {
        return this._recordId ? `kenEventReg_${this._recordId}` : null;
    }

    _saveRegistrationDraft() {
        try {
            if (!this._draftKey) return;
            const draft = {
                ts: Date.now(),
                participants: this.participants,
                currentStep: this.currentStep,
                registrationType: this.registrationType,
                selectedSessionIds: Array.from(this.selectedSessionIds || [])
            };
            sessionStorage.setItem(this._draftKey, JSON.stringify(draft));
        } catch (e) { /* storage unavailable — ignore */ }
    }

    _restoreRegistrationDraft() {
        try {
            if (!this._draftKey) return false;
            const raw = sessionStorage.getItem(this._draftKey);
            if (!raw) return false;
            const draft = JSON.parse(raw);
            if (!draft || !Array.isArray(draft.participants) || !draft.participants.length) return false;
            // Only resurrect a recent draft (within 60 min) so stale state doesn't linger.
            if (draft.ts && (Date.now() - draft.ts) > 3600000) {
                sessionStorage.removeItem(this._draftKey);
                return false;
            }
            this.participants = draft.participants;
            if (draft.currentStep) this.currentStep = draft.currentStep;
            if (draft.registrationType) this.registrationType = draft.registrationType;
            if (Array.isArray(draft.selectedSessionIds)) {
                this.selectedSessionIds = new Set(draft.selectedSessionIds);
            }
            // Re-check the group rows that correspond to restored group participants.
            const restoredGroupIds = new Set(
                this.participants.filter(p => p.type === 'group').map(p => p.groupId)
            );
            this.groups = (this.groups || []).map(g => ({ ...g, selected: restoredGroupIds.has(g.id) }));
            return true;
        } catch (e) {
            return false;
        }
    }

    _clearRegistrationDraft() {
        try { if (this._draftKey) sessionStorage.removeItem(this._draftKey); } catch (e) { /* ignore */ }
    }

    handleParticipantSelect(e) {
        const id = e.target.dataset.id;
        const checked = e.target.checked;
        this.participants = this.participants.map(p => p.id === id ? { ...p, selected: checked } : p);
    }

    handleSelectAll(e) {
        const checked = e.target.checked;
        const pagedIds = new Set(this.pagedParticipants.map(p => p.id));
        this.participants = this.participants.map(p => pagedIds.has(p.id) ? { ...p, selected: checked } : p);
    }

    handleMealsToggle(e) {
        const id = e.target.dataset.id;
        const checked = e.target.checked;
        // Clear any dietary preference when meals are turned off — it only applies with meals.
        this.participants = this.participants.map(p =>
            p.id === id ? { ...p, meals: checked, dietaryPref: checked ? p.dietaryPref : '' } : p
        );
        this._saveRegistrationDraft();
    }

    handleDietaryChange(e) {
        const id = e.target.dataset.id;
        const val = e.target.value;
        this.participants = this.participants.map(p => p.id === id ? { ...p, dietaryPref: val } : p);
        this._saveRegistrationDraft();
    }

    handleSearchChange(e) {
        this.searchQuery = e.target.value;
        this.currentPage = 1;
    }

    handlePrevPage() {
        if (this.currentPage > 1) this.currentPage--;
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) this.currentPage++;
    }

    handlePageClick(e) {
        this.currentPage = parseInt(e.target.dataset.page, 10);
    }

    // -- Handlers: sessions --
    handleAllSessionsRowClick(e) {
        const dateKey = e.currentTarget.dataset.datekey;
        const dg = this.dateGroups.find(d => d.dateKey === dateKey);
        if (!dg) return;
        const allSelected = dg.allSelected;
        this._setGroupSessions(dateKey, !allSelected);
    }

    handleAllSessionsChange(e) {
        e.stopPropagation();
        const dateKey = e.target.dataset.datekey;
        this._setGroupSessions(dateKey, e.target.checked);
    }

    _setGroupSessions(dateKey, checked) {
        const newSet = new Set(this.selectedSessionIds);
        const dg = this.dateGroups.find(d => d.dateKey === dateKey);
        if (!dg) return;
        dg.sessions.forEach(s => {
            if (checked) newSet.add(s.id);
            else newSet.delete(s.id);
        });
        this.selectedSessionIds = newSet;
        this.sessions = this.sessions.map(s => {
            if (s.sessionDate === dateKey) return { ...s, checked: newSet.has(s.id) };
            return s;
        });
        this._buildDateGroups();
    }

    handleSessionRowClick(e) {
        const id = e.currentTarget.dataset.id;
        const dateKey = e.currentTarget.dataset.datekey;
        this._toggleSession(id, dateKey);
    }

    handleSessionChange(e) {
        e.stopPropagation();
        const id = e.target.dataset.id;
        const dateKey = e.target.dataset.datekey;
        this._toggleSession(id, dateKey);
    }

    _toggleSession(id, dateKey) {
        const newSet = new Set(this.selectedSessionIds);
        if (newSet.has(id)) newSet.delete(id);
        else newSet.add(id);
        this.selectedSessionIds = newSet;
        this.sessions = this.sessions.map(s => s.id === id ? { ...s, checked: newSet.has(s.id) } : s);
        this._buildDateGroups();
    }

    // -- Navigation --
    handleBack() {
        if (this.currentStep > 1) this.currentStep--;
    }

    handleNext() {
        if (this.currentStep === 1) {
            if (this.participants.length === 0) {
                this._showToast('Error', 'Please add at least one participant.', 'error');
                return;
            }
            // Dietary preference is required for any participant who has opted for meals.
            if (this.eventData && this.eventData.collectDietary) {
                const missingDietary = this.participants.some(
                    p => p.meals && !(p.dietaryPref && String(p.dietaryPref).trim())
                );
                if (missingDietary) {
                    this._showToast('Error', 'Please select a dietary preference for each participant who has opted for meals.', 'error');
                    return;
                }
            }
            this.currentStep = 2;
        } else if (this.currentStep === 2) {
            if (this.selectedSessionIds.size === 0) {
                this._showToast('Error', 'Please select at least one session.', 'error');
                return;
            }
            this.currentStep = 3;
        }
    }

    handleFinalRegister() {
        if (this.isLoading) return;
        this.isLoading = true;

        const participantsPayload = this.participants
            .filter(p => p.selected)
            .map(p => ({
                type: p.type === 'myself' ? 'Myself' : (p.type === 'group' ? 'Group' : 'Guest'),
                name: p.name || '',
                email: p.email || '',
                phone: p.type === 'group' ? '' : (p.phone || ''),
                groupId: p.type === 'group' ? (p.groupId || '') : '',
                memberCount: p.type === 'group' ? (p.memberCount || 0) : 1,
                meals: !!p.meals,
                dietaryPref: p.dietaryPref || ''
            }));

        const payload = JSON.stringify({
            sessionIds: [...this.selectedSessionIds],
            participants: participantsPayload
        });

        saveEventRegistrations({
            payload,
            constituentRoleId: this.constituentRoleId
        })
        .then(() => {
            this._showToast('Success', 'Registration successful!', 'success');
            setTimeout(() => this.closeModal(), 1500);
        })
        .catch(err => {
            this._showToast('Error', err.body ? err.body.message : 'Registration failed.', 'error');
            this.isLoading = false;
        });
    }

    handleFillSurvey(event) {
        const participantId = event.currentTarget.dataset.id;
        if (this.questionnaireId) {
            // Persist the in-progress registration before leaving so guests/group
            // selections are restored when the survey returns us here.
            this._saveRegistrationDraft();
            // Open the survey form in record-id mode against the EVENT — the form
            // resolves the event's Survey__c lookup directly. After submit it returns
            // here via browser history (no long returnUrl param needed).
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: { name: 'survey_form__c' },
                state: { recId: this._recordId, participantId }
            });
        } else {
            this._showToast('Info', 'No survey configured for this event.', 'info');
        }
    }

    handleShareSurvey() {
        if (this.questionnaireId) {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: { name: 'survey_detail__c' },
                state: { surveyId: this.questionnaireId }
            });
        }
    }

    closeModal() {
        if (this.embeddedModal === true || this.embeddedModal === 'true') {
            this.dispatchEvent(new CustomEvent('closeregistration', { bubbles: true, composed: true }));
            return;
        }
        const rid = this._recordId;
        if (rid) {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: { url: `${basePath}/event/event-detail?recordId=${rid}` }
            });
        } else {
            this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'all_events__c' } });
        }
    }

    _showToast(title, message, variant) {
        try {
            this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
        } catch (e) {
            this.dispatchEvent(new CustomEvent('showtoast', { detail: { title, message, variant }, bubbles: true, composed: true }));
        }
    }
}