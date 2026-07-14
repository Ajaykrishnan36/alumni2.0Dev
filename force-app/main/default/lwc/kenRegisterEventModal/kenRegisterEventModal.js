import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEventSchedules from '@salesforce/apex/KenPortalEventController.getEventSchedules';
import searchAudienceGroups from '@salesforce/apex/KenAudienceEngineService.searchAudienceGroups';
import getCurrentParticipantDetails from '@salesforce/apex/KenPortalEventController.getCurrentParticipantDetails';
import saveRegistrations from '@salesforce/apex/KenPortalEventController.saveRegistrations';
import { getPortalConfigs } from 'c/kenThemeConfig';

export default class KenRegisterEventModal extends LightningElement {
    @api eventId;
    @api eventData;
    @api isMultiDay = false;

    @track currentStep = 1;
    @track registrationType = 'myself';
    @track participants = [];
    @track guestName = '';
    @track guestEmail = '';
    @track guestPhone = '';
    @track searchQuery = '';
    @track currentPage = 1;
    @track groups = [];
    @track sessions = [];
    @track dateGroups = [];
    @track selectedSessionIds = new Set();
    @track isLoading = false;
    // When the org has Disable_Event_Fee__c enabled, all fee/payment UI is hidden.
    @track feeDisabled = false;

    constituentRoleId = null;
    pageSize = 5;
    _participantIdCounter = 1;

    connectedCallback() {
        try {
            this.constituentRoleId = localStorage.getItem('constituentRoleId') || sessionStorage.getItem('constituentRoleId');
        } catch (e) {
            this.constituentRoleId = null;
        }
        this._loadCurrentUser();
        this._loadGroups();

        getPortalConfigs()
            .then(cfg => { this.feeDisabled = cfg?.disableEventFee === true; })
            .catch(() => {});
    }

    // Master switch for all fee/payment UI in this modal.
    get showFees() { return !this.feeDisabled; }

    _loadCurrentUser() {
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
        searchAudienceGroups({ searchTerm: '', limitSize: 20 })
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
        return raw.split(',').filter(o => o.trim()).map(o => ({
            value: o.trim(),
            label: o.trim(),
            selected: o.trim() === currentValue
        }));
    }

    @wire(getEventSchedules, { eventId: '$eventId', constituentRoleId: '$constituentRoleId' })
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

    // -- Mode getters --
    get isMyselfMode() { return this.registrationType === 'myself'; }
    get isBulkMode() { return this.registrationType === 'bulk'; }
    get myselfBtnClass() { return this.isMyselfMode ? 'mode-btn active' : 'mode-btn'; }
    get bulkBtnClass() { return this.isBulkMode ? 'mode-btn active' : 'mode-btn'; }

    // -- Meal/dietary getters --
    get showMealsColumn() { return !!(this.eventData && this.eventData.offerMeals); }
    get showDietaryColumn() { return !!(this.eventData && this.eventData.collectDietary); }
    get showFeeLabel() { return this.showFees && !!(this.eventData && !this.eventData.noFee && this.sessions.length > 0); }
    get sessionPriceLabel() {
        const priced = this.sessions.find(s => s.price > 0);
        return priced ? priced.price.toLocaleString('en-IN') : '0';
    }

    // -- Participants getters --
    get participantCount() { return this.participants.length; }
    get hasParticipants() { return this.participants.length > 0; }
    get hasGroups() { return this.groups.length > 0; }

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
            dietaryOptions: this._buildDietaryOptions(p.dietaryPref || '')
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
        return sessionSum * this.participantCount;
    }

    get totalAmountFormatted() {
        return this.totalAmount.toLocaleString('en-IN');
    }

    get sessionSubtotal() {
        return this.selectedSessions.reduce((sum, s) => sum + (s.price || 0), 0).toLocaleString('en-IN');
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
    handleGuestEmailChange(e) { this.guestEmail = e.target.value; }
    handleGuestPhoneChange(e) { this.guestPhone = e.target.value; }

    handleAddGuest() {
        if (!this.guestName || !this.guestEmail) {
            this._showToast('Error', 'Name and Email are required.', 'error');
            return;
        }
        const guestCount = this.participants.filter(p => p.type === 'guest').length;
        if (guestCount >= 5) {
            this._showToast('Error', 'Maximum 5 guests can be added.', 'error');
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
        this.guestPhone = '';
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
    }

    // -- Handlers: participants table --
    handleDeleteParticipant(e) {
        const id = e.currentTarget.dataset.id;
        this.participants = this.participants.filter(p => p.id !== id);
        this.groups = this.groups.map(g => {
            if (`group_${g.id}` === id) return { ...g, selected: false };
            return g;
        });
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
        this.participants = this.participants.map(p => p.id === id ? { ...p, meals: checked } : p);
    }

    handleDietaryChange(e) {
        const id = e.target.dataset.id;
        const val = e.target.value;
        this.participants = this.participants.map(p => p.id === id ? { ...p, dietaryPref: val } : p);
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

        const participantData = this.participants.map(p => ({
            name: p.name,
            email: p.email,
            phone: p.phone,
            type: p.type,
            meals: p.meals,
            dietaryPref: p.dietaryPref
        }));

        saveRegistrations({
            eventId: this.eventId,
            constituentRoleId: this.constituentRoleId,
            sessionIds: [...this.selectedSessionIds],
            participants: JSON.stringify(participantData)
        })
            .then(() => {
                this._showToast('Success', 'Registration successful!', 'success');
                this.closeModal();
            })
            .catch(err => {
                this._showToast('Error', err.body ? err.body.message : 'Registration failed.', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    closeModal() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    _showToast(title, message, variant) {
        try {
            this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
        } catch (e) {
            this.dispatchEvent(new CustomEvent('showtoast', { detail: { title, message, variant }, bubbles: true, composed: true }));
        }
    }
}