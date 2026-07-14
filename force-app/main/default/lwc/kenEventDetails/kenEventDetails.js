import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getEventDetails from '@salesforce/apex/KenPortalEventController.getEventDetails';
import getRegisteredSessions from '@salesforce/apex/KenPortalEventController.getRegisteredSessions';
import getEventSchedules from '@salesforce/apex/KenPortalEventController.getEventSchedules';
import CancelSessionRegistration from '@salesforce/apex/KenPortalEventController.cancelRegistrations';
import saveEventUpdateLinks from '@salesforce/apex/KenPortalEventController.saveEventUpdateLinks';
import getMealOptedCounts from '@salesforce/apex/KenPortalEventController.getMealOptedCounts';
import getEventParticipants from '@salesforce/apex/KenPortalEventController.getEventParticipants';
import deleteHostedEvent from '@salesforce/apex/KenPortalEventController.deleteHostedEvent';
import getEventUpdatesData from '@salesforce/apex/KenPortalEventController.getEventUpdatesData';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import defaultProfileImage from '@salesforce/resourceUrl/defaultProfileImage';
import basePath from '@salesforce/community/basePath';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import FORM_FACTOR from '@salesforce/client/formFactor';
export default class KenEventDetails extends NavigationMixin(LightningElement) {

    recordId;
    constituentRoleId;

    @track event;
    @track registeredSessions = [];
    @track wiredRegisteredSessionsData = [];
    @track schedules = [];
    @track isMobile = false;
    @track wiredEventSchedulesResult = [];
    @track activeTab = 'about';
    @track showCancelConfirmation = false;
    @track mealOptedMap = {};
    @track participants = [];
    @track participantSearch = '';
    @track participantPage = 1;
    participantPageSize = 8;
    @track showPhotosModal = false;
    @track showHighlightsModal = false;
    @track photosLinkInput = '';
    @track highlightsLinkInput = '';
    @track showDeleteConfirm = false;
    @track eventUpdatesData = { preEventSurveys: [], sessions: [] };
    @track showFilterDropdown = false;
    @track filterMeals = '';
    @track filterCustomForm = '';
    // When the org has Disable_Event_Fee__c enabled, the fee badge is hidden.
    @track feeDisabled = false;
    selectedSessionId;
    toastTitle;
    toastVariant;
    toastMessage;
    showToast = false;

    get hasCategories() {
        return this.event && this.event.categories && this.event.categories.length > 0;
    }

    get showSpinner() {
        return !this.event;
    }

    get isMultiDay() {
        return this.event && this.event.eventType == 'Multi-day';
    }

    get isAboutTab() {
        return this.activeTab === 'about';
    }

    get isScheduleTab() {
        return this.activeTab === 'schedule';
    }

    get aboutTabClass() {
        return this.activeTab === 'about' ? 'event-tab-btn active' : 'event-tab-btn';
    }

    get scheduleTabClass() {
        return this.activeTab === 'schedule' ? 'event-tab-btn active' : 'event-tab-btn';
    }

    get firstCategory() {
        return this.event?.categories?.[0] || '';
    }

    get showEventFee() {
        return this.event && !this.event.noFee && this.event.eventFee;
    }

    get showFeeBadge() {
        return !this.feeDisabled;
    }

    // Master switch for fee/payment UI (badge, payment columns).
    get showFees() {
        return !this.feeDisabled;
    }

    // Participants table column count for the empty-state row (drops 2 payment columns when fees are off).
    get participantEmptyColspan() {
        return this.feeDisabled ? 7 : 9;
    }

    get priceLabel() {
        if (!this.event) return '';
        if (!this.event.noFee && this.event.eventFee) return `₹${Number(this.event.eventFee).toFixed(2)}`;
        const hasSessionFee = this.schedules && this.schedules.some(s => s.price && !s.noFee);
        if (hasSessionFee) return 'Session Fee';
        return 'Free';
    }

    get eventLocationType() {
        if (!this.schedules || this.schedules.length === 0) return this.event?.location || '';
        const types = this.schedules.map(s => (s.locationType || s.Location_Type__c || '').toLowerCase());
        const hasOnline = types.includes('online');
        const hasOnsite = types.some(t => t === 'onsite' || t === 'offline');
        const hasHybrid = types.includes('hybrid');
        if (hasHybrid || (hasOnline && hasOnsite)) return 'Hybrid';
        if (hasOnsite) return 'Offline';
        if (hasOnline) return 'Online';
        return this.event?.location || '';
    }

    get formattedLanguage() {
        if (!this.event?.language) return '';
        return this.event.language.split(';').map(l => l.trim()).filter(l => l).join(', ');
    }

    get hasMeals() {
        return this.event?.offerMeals && this.mealsByDate.length > 0;
    }

    get mealsByDate() {
        const map = {};
        if (!this.schedules) return [];
        this.schedules.forEach(s => {
            if (s.meals && s.sessionDate) {
                if (!map[s.sessionDate]) map[s.sessionDate] = { meals: new Set(), raw: s.rawDate };
                s.meals.split(';').filter(m => m.trim()).forEach(m => map[s.sessionDate].meals.add(m.trim()));
            }
        });
        return Object.keys(map).sort().map(date => {
            const raw = map[date].raw;
            const count = raw && this.mealOptedMap ? this.mealOptedMap[raw] : undefined;
            const showOpted = this.isHost && count !== undefined && count !== null;
            return {
                date,
                meals: Array.from(map[date].meals).join(', '),
                optedLabel: showOpted ? `${count} Opted` : ''
            };
        });
    }

    get hasExpectations() {
        return this.event?.expectations && this.event.expectations.includes('\n');
    }

    get expectationsList() {
        if (!this.event?.expectations) return [];
        return this.event.expectations
            .split(/\r?\n/)
            .filter(line => line.trim())
            .map((text, idx) => ({ id: idx, text: text.trim() }));
    }

    get toastClasses() {
        return `modern-toast ${this.toastVariant}`;
    }

    // Mobile-specific getters
    get showMobileView() {
        return this.isMobile && this.event;
    }

    get showDesktopView() {
        return !this.isMobile;
    }

    get mobileEventTitle() {
        return this.event?.title || '';
    }

    get mobileEventType() {
        return this.event?.eventType || '';
    }

    get mobileEventImage() {
        return this.event?.image || '';
    }

    get mobileEventDescription() {
        return this.event?.description || '';
    }

    get mobileEventExpectations() {
        return this.event?.expectations || '';
    }

    get mobileEventCategories() {
        return this.event?.categories || [];
    }

    get mobileEventDate() {
        return this.event?.startDate || '';
    }

    get mobileEventTime() {
        // Format time as "8PM" or similar
        if (this.event?.startTime) {
            const time = this.formatTime(this.event.startTime);
            return time;
        }
        return '';
    }

    get mobileEventParticipants() {
        return this.event?.participantsCount || '';
    }

    get mobileEventPostedDate() {
        return this.event?.postedDate || '';
    }

    get category() {
        return this.event?.categories?.[0] || '';
    }

    get isMultiDayEvent() {
        return this.event?.eventType === 'Multi-day';
    }

    get isOneDayEvent() {
        return this.event?.eventType === 'One-day';
    }

    get eventDurationBadge() {
        return this.isMultiDayEvent ? 'Multi-day' : 'One-day';
    }

    get defaultProfileImage() {
        return defaultProfileImage;
    }

    // Group schedules by date
    get groupedSchedules() {
        const map = {};
        if (!this.schedules) return [];
        this.schedules.forEach(sch => {
            if (!map[sch.sessionDate]) {
                map[sch.sessionDate] = [];
            }
            map[sch.sessionDate].push(sch);
        });
        // Return as array of { date, schedules }
        return Object.keys(map).sort().map(date => ({
            date,
            schedules: map[date]
        }));
    }

    get toastIcon() {
        switch (this.toastVariant) {
            case 'success':
                return 'M10.95 15.95L16.2375 10.6625L15.1875 9.6125L10.95 13.85L8.8125 11.7125L7.7625 12.7625L10.95 15.95ZM12 20C10.9625 20 9.9875 19.803 9.075 19.409C8.1625 19.0155 7.36875 18.4813 6.69375 17.8063C6.01875 17.1313 5.4845 16.3375 5.091 15.425C4.697 14.5125 4.5 13.5375 4.5 12.5C4.5 11.4625 4.697 10.4875 5.091 9.575C5.4845 8.6625 6.01875 7.86875 6.69375 7.19375C7.36875 6.51875 8.1625 5.98425 9.075 5.59025C9.9875 5.19675 10.9625 5 12 5C13.0375 5 14.0125 5.19675 14.925 5.59025C15.8375 5.98425 16.6313 6.51875 17.3063 7.19375C17.9813 7.86875 18.5155 8.6625 18.909 9.575C19.303 10.4875 19.5 11.4625 19.5 12.5C19.5 13.5375 19.303 14.5125 18.909 15.425C18.5155 16.3375 17.9813 17.1313 17.3063 17.8063C16.6313 18.4813 15.8375 19.0155 14.925 19.409C14.0125 19.803 13.0375 20 12 20Z';
            case 'warning':
                return 'M1 21H23L12 2L1 21ZM13 18H11V16H13V18ZM13 14H11V10H13V14Z';
            case 'error':
                return 'M12 2C6.48 2 2 6.48 2 12C2 17.52 6.48 22 12 22C17.52 22 22 17.52 22 12C22 6.48 17.52 2 12 2ZM13 17H11V15H13V17ZM13 13H11V7H13V13Z';
            default:
                return 'M9 16.17L4.83 12L3.41 13.41L9 19L21 7L19.59 5.59L9 16.17Z';
        }
    }

    get toastIconColor() {
        switch (this.toastVariant) {
            case 'success':
                return '#4CAF50';
            case 'warning':
                return '#FF9800';
            case 'error':
                return '#F44336';
            default:
                return '#4CAF50';
        }
    }

    get showRegisterButton() {
        if (this.isHost) return false;
        if (this.isRegistered) return false;
        if (this.event?.eventStatus !== 'Approved') return false;
        return this.schedules.some(schedule => !schedule.isRegistered && !schedule.isCompleted);
    }

    get isRegistered() {
        if (this.registeredSessions && this.registeredSessions.length > 0) return true;
        return this.schedules && this.schedules.some(s => s.isRegistered);
    }

    get registeredStatusLabel() {
        const now = new Date();
        const start = this.event?.startDate ? new Date(this.event.startDate) : null;
        if (!start) return 'Upcoming';
        const endBase = this.event?.endDate ? new Date(this.event.endDate) : start;
        const endOfDay = new Date(endBase.getFullYear(), endBase.getMonth(), endBase.getDate(), 23, 59, 59);
        if (now < start) return 'Upcoming';
        if (now > endOfDay) return 'Completed';
        return 'Ongoing';
    }

    handleViewRegistrationSummary() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'registration_summary__c' },
            state: { recordId: this.recordId }
        });
    }

    handleJoinEvent() {
        const reg = (this.schedules || []).find(s => s.isRegistered && (s.sessionLink || s.Session_Link__c));
        const link = reg ? (reg.sessionLink || reg.Session_Link__c) : null;
        if (link) {
            window.open(link, '_blank');
        } else {
            this.showToastMessage('Join Event', 'No join link available yet.', 'info');
        }
    }

    connectedCallback() {
        this.constituentRoleId = localStorage.getItem('ConstituentRoleId');
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            this.feeDisabled = color?.disableEventFee === true;
        }).catch(() => {
            console.log('Error getting primary color');
        });
        
        this.checkScreenSize();
        window.addEventListener('resize', this.handleResize.bind(this));
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this.handleResize.bind(this));
    }

    // Registration is created via a separate page, so getRegisteredSessions can return
    // a stale cached result on arrival (still showing "Register"). Force one refresh
    // once the wire has resolved so the button reflects the latest registration.
    renderedCallback() {
        if (!this._didRegRefresh && this.wiredRegisteredSessionsData &&
            this.wiredRegisteredSessionsData.data !== undefined) {
            this._didRegRefresh = true;
            refreshApex(this.wiredRegisteredSessionsData);
            if (this.wiredEventSchedulesResult && this.wiredEventSchedulesResult.data !== undefined) {
                refreshApex(this.wiredEventSchedulesResult);
            }
        }
    }

    checkScreenSize() {
        this.isMobile = window.innerWidth <= 768;
    }

    handleResize() {
        this.checkScreenSize();
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(currentPageReference) {
        if (currentPageReference) {
            this.recordId = currentPageReference.state?.recordId;
            console.log('Current Page Record ID:', this.recordId);
        }
    }

    @wire(getEventDetails, { recordId: '$recordId' })
    wiredEventDetails({ error, data }) {
        if (data) {
            this.event = {
                ...data,
                categories: data.categories ? data.categories.split(';') : [],
                formattedDateRange: data.startDate ? this.formatDateRange(data.startDate, data.endDate) : null,
                postedDate: data.postedDate ? this.formatDate(data.postedDate) : null
            };
        } else if (error) {
            console.log('Error fetching event details:', error);
        }
    }

    @wire(getRegisteredSessions, { EventId: '$recordId', constituentRoleId: '$constituentRoleId' })
    wiredRegisteredSessions(response) {
        this.wiredRegisteredSessionsData = response;
        const { error, data } = response;
        if (data) {
            this.registeredSessions = data;
            console.log('Registered Sessions:', JSON.stringify(this.registeredSessions));
        } else if (error) {
            console.log('Error fetching registered sessions:', error);
        }
    }

    @wire(getEventSchedules, { eventId: '$recordId', constituentRoleId: '$constituentRoleId' })
    wiredEventSchedules(response) {
        this.wiredEventSchedulesResult = response;
        const { error, data } = response;
        if (data) {
            console.log('Event schedules:', JSON.stringify(data));
            this.schedules = this.processSchedules(data);
            console.log('Processed schedules:', JSON.stringify(this.schedules));
        } else if (error) {
            console.log('Error fetching event schedules:', error);
        }
    }

    @wire(getMealOptedCounts, { eventId: '$recordId' })
    wiredMealCounts({ data }) {
        if (data) {
            this.mealOptedMap = data;
        }
    }

    handleTabAbout() {
        this.activeTab = 'about';
    }

    handleTabSchedule() {
        this.activeTab = 'schedule';
    }

    handleTabUpdates() {
        this.activeTab = 'updates';
    }

    handleTabParticipants() {
        this.activeTab = 'participants';
    }

    @wire(getEventParticipants, { eventId: '$recordId' })
    wiredParticipants({ data }) {
        if (data) this.participants = data;
    }

    @wire(getEventUpdatesData, { eventId: '$recordId' })
    wiredEventUpdates({ data }) {
        if (data) this.eventUpdatesData = data;
    }

    get hasPreEventSurveys() { return this.eventUpdatesData?.preEventSurveys?.length > 0; }
    get hasSessionFeedbacks() { return this.eventUpdatesData?.sessions?.length > 0; }

    _mapSurveyCard(s) {
        const start = s.startDate ? this.formatDate(s.startDate) : null;
        const end = s.endDate ? this.formatDate(s.endDate) : null;
        const periodLabel = start && end ? `${start} – ${end}` : (start || '–');
        return {
            id: s.id,
            name: s.name,
            periodLabel,
            questionLabel: s.questionCount > 0 ? String(s.questionCount) : '––',
            responseLabel: s.responseCount > 0 ? String(s.responseCount) : '––',
            hasQuestionnaire: s.hasQuestionnaire,
            isCompleted: s.status === 'Completed',
            isActive: s.status === 'Active',
            isUpcoming: s.status === 'Upcoming'
        };
    }

    get processedPreEventSurveys() {
        return (this.eventUpdatesData?.preEventSurveys || []).map(s => this._mapSurveyCard(s));
    }

    get processedSessionFeedbacks() {
        return (this.eventUpdatesData?.sessions || []).map(s => ({
            sessionId: s.sessionId,
            sessionName: s.sessionName,
            sessionDate: s.sessionDate ? this.formatDate(s.sessionDate) : '–',
            hasSurvey: !!s.hasSurvey,
            surveyId: s.surveyId,
            questionLabel: s.questionCount > 0 ? String(s.questionCount) : '––',
            responseLabel: s.responseCount > 0 ? String(s.responseCount) : '––',
            hasQuestionnaire: !!s.hasQuestionnaire,
            isCompleted: s.status === 'Completed',
            isActive: s.status === 'Active',
            isUpcoming: s.status === 'Upcoming',
            statusClass: s.status === 'Completed' ? 'eu-fb-completed' : (s.status === 'Active' ? 'eu-fb-active' : 'eu-fb-upcoming')
        }));
    }

    // ---- Participants tab (host only, hidden for In Review) ----
    get isInReview() { return this.event && this.event.eventStatus === 'In Review'; }
    get showParticipantsTab() { return this.isHost && !this.isInReview; }
    get isParticipantsTab() { return this.activeTab === 'participants'; }
    get participantsTabClass() {
        return this.activeTab === 'participants' ? 'event-tab-btn active' : 'event-tab-btn';
    }

    get processedParticipants() {
        return (this.participants || []).map(p => ({
            id: p.id,
            name: p.name,
            batchLabel: p.batch ? `Batch - ${p.batch}` : '',
            email: p.email,
            phone: p.phone,
            sessionsCount: p.sessionsCount,
            mealsIncluded: !!p.mealsIncluded,
            mealsLabel: p.mealsIncluded ? 'Yes' : 'No',
            diet: p.diet || '-',
            customFormFilled: !!p.customFormFilled,
            customFormLabel: p.customFormFilled ? 'Filled' : 'Not filled',
            customFormClass: p.customFormFilled ? 'cf-badge cf-filled' : 'cf-badge cf-notfilled',
            registeredOnLabel: p.registeredOn ? this.formatDate(p.registeredOn) : '',
            paymentMethod: p.paymentMethod || '-',
            transactionId: p.transactionId || '-'
        }));
    }

    get filteredParticipants() {
        let results = this.processedParticipants;
        const q = (this.participantSearch || '').trim().toLowerCase();
        if (q) {
            results = results.filter(p =>
                (p.name || '').toLowerCase().includes(q) || (p.email || '').toLowerCase().includes(q));
        }
        if (this.filterMeals === 'yes') results = results.filter(p => p.mealsIncluded);
        if (this.filterMeals === 'no') results = results.filter(p => !p.mealsIncluded);
        if (this.filterCustomForm === 'filled') results = results.filter(p => p.customFormFilled);
        if (this.filterCustomForm === 'notfilled') results = results.filter(p => !p.customFormFilled);
        return results;
    }

    get hasActiveFilters() { return this.filterMeals !== '' || this.filterCustomForm !== ''; }
    get activeFilterCount() {
        let c = 0;
        if (this.filterMeals !== '') c++;
        if (this.filterCustomForm !== '') c++;
        return c;
    }
    get filterBtnClass() { return this.hasActiveFilters ? 'pt-filter-btn active' : 'pt-filter-btn'; }

    get totalParticipantPages() {
        return Math.max(1, Math.ceil(this.filteredParticipants.length / this.participantPageSize));
    }
    get pagedParticipants() {
        const start = (this.participantPage - 1) * this.participantPageSize;
        return this.filteredParticipants.slice(start, start + this.participantPageSize);
    }
    get hasParticipantRows() { return this.filteredParticipants.length > 0; }
    get showParticipantPagination() { return this.filteredParticipants.length > this.participantPageSize; }
    get isParticipantPrevDisabled() { return this.participantPage <= 1; }
    get isParticipantNextDisabled() { return this.participantPage >= this.totalParticipantPages; }
    get participantPageLabel() { return `Page ${this.participantPage} of ${this.totalParticipantPages}`; }

    handleParticipantSearch(e) {
        this.participantSearch = e.target.value || '';
        this.participantPage = 1;
    }
    handleParticipantPrev() { if (this.participantPage > 1) this.participantPage--; }
    handleParticipantNext() { if (this.participantPage < this.totalParticipantPages) this.participantPage++; }

    handleDownloadReport() {
        const rows = this.filteredParticipants;
        const headers = ['Participant', 'Batch', 'Email', 'Phone', 'Sessions', 'Meals Included', 'Diet', 'Custom Form', 'Registered On', 'Payment Method', 'Transaction ID'];
        const esc = (v) => {
            const s = (v === null || v === undefined) ? '' : String(v);
            return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
        };
        const lines = [headers.join(',')];
        rows.forEach(p => {
            lines.push([
                p.name, p.batchLabel ? p.batchLabel.replace('Batch - ', '') : '', p.email, p.phone,
                p.sessionsCount, p.mealsLabel, p.diet, p.customFormLabel, p.registeredOnLabel,
                p.paymentMethod, p.transactionId
            ].map(esc).join(','));
        });
        const csv = lines.join('\n');
        const filename = `${(this.event && this.event.title ? this.event.title : 'event').replace(/[^a-z0-9]+/gi, '_')}_participants.csv`;
        const encodedUri = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        const a = document.createElement('a');
        a.setAttribute('href', encodedUri);
        a.setAttribute('download', filename);
        a.click();
    }

    // ---- Host / status helpers ----
    get isHost() {
        return this.event && this.event.hostRoleId && this.constituentRoleId
            && this.event.hostRoleId === this.constituentRoleId;
    }
    get isOngoingStatus() { return this.registeredStatusLabel === 'Ongoing'; }
    get isCompletedStatus() { return this.registeredStatusLabel === 'Completed'; }
    get isUpcomingStatus() { return this.registeredStatusLabel === 'Upcoming'; }

    get isRejected() { return this.event && this.event.eventStatus === 'Rejected'; }
    get isApproved() { return this.event && this.event.eventStatus === 'Approved'; }

    get showHostInReviewActions() { return this.isHost && this.isInReview; }
    get showHostRejectedActions() { return this.isHost && this.isRejected; }
    get showHostApprovedActions() { return this.isHost && this.isApproved; }
    get showNonHostActions() { return !this.isHost; }

    get showRejectionReason() { return this.isHost && this.isRejected && this.event?.rejectionReason; }

    get showEventUpdatesTab() {
        if (this.isHost) return this.isApproved;
        return this.isRegistered && (this.isOngoingStatus || this.isCompletedStatus);
    }
    get isUpdatesTab() { return this.activeTab === 'updates'; }
    get updatesTabClass() {
        return this.activeTab === 'updates' ? 'event-tab-btn active' : 'event-tab-btn';
    }

    // ---- Event Updates: photos / highlights ----
    get photosLink() { return this.event?.photosLink || ''; }
    get highlightsLink() { return this.event?.highlightsLink || ''; }
    get hasPhotosLink() { return !!this.photosLink; }
    get hasHighlightsLink() { return !!this.highlightsLink; }
    get showPhotosCard() { return this.isHost || this.hasPhotosLink; }
    get showHighlightsCard() { return this.isHost || this.hasHighlightsLink; }
    get photosBtnLabel() { return this.hasPhotosLink ? 'Change Link' : 'Add Photos Link'; }
    get highlightsBtnLabel() { return this.hasHighlightsLink ? 'Change Link' : 'Add Highlights Link'; }

    handleOpenPhotos() { if (this.photosLink) window.open(this.photosLink, '_blank'); }
    handleOpenHighlights() { if (this.highlightsLink) window.open(this.highlightsLink, '_blank'); }

    handleAddPhotos() {
        this.photosLinkInput = this.photosLink;
        this.showPhotosModal = true;
    }
    handleAddHighlights() {
        this.highlightsLinkInput = this.highlightsLink;
        this.showHighlightsModal = true;
    }
    handlePhotosLinkInput(e) { this.photosLinkInput = e.target.value; }
    handleHighlightsLinkInput(e) { this.highlightsLinkInput = e.target.value; }
    closePhotosModal() { this.showPhotosModal = false; }
    closeHighlightsModal() { this.showHighlightsModal = false; }

    handleSavePhotos() {
        saveEventUpdateLinks({ eventId: this.recordId, photosLink: this.photosLinkInput, highlightsLink: this.highlightsLink })
            .then(() => {
                this.event = { ...this.event, photosLink: this.photosLinkInput };
                this.showPhotosModal = false;
                this.showToastMessage('Saved', 'Photos link saved.', 'success');
            })
            .catch(() => this.showToastMessage('Error', 'Could not save link.', 'error'));
    }
    handleSaveHighlights() {
        saveEventUpdateLinks({ eventId: this.recordId, photosLink: this.photosLink, highlightsLink: this.highlightsLinkInput })
            .then(() => {
                this.event = { ...this.event, highlightsLink: this.highlightsLinkInput };
                this.showHighlightsModal = false;
                this.showToastMessage('Saved', 'Highlights link saved.', 'success');
            })
            .catch(() => this.showToastMessage('Error', 'Could not save link.', 'error'));
    }

    handleGetHelp() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'service_support__c' }
        });
    }

    handleEditEvent() {
        try { sessionStorage.setItem('currentEventId', this.recordId); } catch (e) { /* ignore */ }
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'host_event__c' }
        });
    }

    handleEditAndResubmit() {
        this.handleEditEvent();
    }

    handleDeleteEvent() {
        this.showDeleteConfirm = true;
    }

    handleDeleteCancel() {
        this.showDeleteConfirm = false;
    }

    async handleDeleteConfirm() {
        try {
            this.showDeleteConfirm = false;
            await deleteHostedEvent({ eventId: this.recordId });
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: { name: 'host_event__c' }
            });
        } catch (e) {
            this.showToastMessage('Error', e?.body?.message || 'Could not delete event.', 'error');
        }
    }

    handleToggleFilterDropdown() {
        this.showFilterDropdown = !this.showFilterDropdown;
    }

    handleFilterMealsChange(e) {
        this.filterMeals = e.target.value;
        this.participantPage = 1;
    }

    handleFilterCustomFormChange(e) {
        this.filterCustomForm = e.target.value;
        this.participantPage = 1;
    }

    handleClearFilters() {
        this.filterMeals = '';
        this.filterCustomForm = '';
        this.participantPage = 1;
        this.showFilterDropdown = false;
    }

    handleSurveyViewDetails(e) {
        const surveyId = e.currentTarget.dataset.id;
        if (!surveyId) return;
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'survey_detail__c' },
            state: { surveyId: surveyId }
        });
    }

    handleSurveySetup() {
        try { sessionStorage.setItem('currentEventId', this.recordId); } catch (e) { /* ignore */ }
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'host_event__c' }
        });
    }

    navigateToEventsHome() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'all_events__c'
            }
        });
    }

    handleBackButton() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'all_events__c'
            }
        });
    }

    handleRegister() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'event_register__c' },
            state: { recordId: this.recordId }
        });
    }

    handleCancelRegistration(event) {
        this.selectedSessionId = event.target.dataset.id;
        this.showCancelConfirmation = true;
    }

    handleCancelButtonMouseDown(event) {
        // Prevent event bubbling to parent div
        event.stopPropagation();
    }

    handleBackToSelection() {
        this.showCancelConfirmation = false;
        this.selectedSessionId = null;
    }

    async handleFinalCancel() {
        try {
            await CancelSessionRegistration({ sessionIds: [this.selectedSessionId], constituentRoleId: this.constituentRoleId });
            await this.refreshSchedules();
            this.selectedSessionId = null;
            this.showCancelConfirmation = false;

            this.showToastMessage('Cancellation Successful!', 'Registration cancelled successfully', 'success');
        } catch (error) {
            console.log('Error cancelling registration:', error);
        }
    }

    async refreshSchedules() {
        try {
            await refreshApex(this.wiredEventSchedulesResult);
        } catch (error) {
            console.log('Error refreshing schedules:', error);
        }
    }

    async showToastMessage(title, message, variant) {
        this.toastTitle = title;
        this.toastMessage = message;
        this.toastVariant = variant;
        this.showToast = true;

        // if (this.toastTitle == 'Registration Successful!' || this.toastTitle == 'Cancellation Successful!') {
        //     console.log('Refreshing Registered Sessions');
        //     await refreshApex(this.wiredRegisteredSessionsData);
        //     await refreshApex(this.wiredEventSchedulesResult);

        //     const eventSchedule = this.template.querySelector('c-event-schedule');
        //     if (eventSchedule) {
        //         console.log('test'); 
        //         eventSchedule.refreshSchedules();
        //     }
        // }

        // Auto hide after 3 seconds
        setTimeout(() => {
            this.hideToast();
        }, 3000);
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.schedules = this.schedules.map((item, i) => ({
            ...item,
            expanded: item.id == id ? !item.expanded : false,
            expandedIcon: item.id == id ?
                (!item.expanded ? 'utility:chevronup' : 'utility:chevrondown') :
                'utility:chevrondown'
        }));
    }

    processSchedules(data) {
        if (!data || data.length === 0) return [];

        const sorted = [...data].sort((a, b) => {
            const aDateTime = this.getDateTime(a.sessionDate, a.startTime);
            const bDateTime = this.getDateTime(b.sessionDate, b.startTime);
            return aDateTime - bDateTime;
        });

        return sorted.map((item, index) => {
            // Determine speaker avatar image
            let speakerAvatarImage = this.defaultProfileImage;
            if (item.speakers && item.speakers.length > 0 && item.speakers[0].image) {
                speakerAvatarImage = item.speakers[0].image;
            }

            return {
                ...item,
                startTime: item.startTime ? this.formatTime(item.startTime) : null,
                endTime: item.endTime ? this.formatTime(item.endTime) : null,
                sessionDate: item.sessionDate ? this.formatDate(item.sessionDate) : null,
                rawDate: item.sessionDate || null,
                isCompleted: this.checkIsCompleted(item),
                sessionNumber: index + 1,
                hasSpeakers: item.speakers && item.speakers.length > 0,
                meals: item.meals || null,
                expanded: false,
                expandedIcon: 'utility:chevronright',
                speakerAvatarImage: speakerAvatarImage
            };
        });
    }

    checkIsCompleted(item) {
    if (!item.sessionDate || item.startTime == null) {
        return false;
    }

    const sessionDateObj = new Date(item.sessionDate);
    const sessionDateTime = new Date(sessionDateObj);

    sessionDateTime.setMilliseconds(item.startTime);

    return new Date() > sessionDateTime;
    }

    getDateTime(dateStr, millisFromMidnight) {
        const date = new Date(dateStr);
        return new Date(date.getTime() + millisFromMidnight);
    }

    formatTime(milliseconds) {
        const date = new Date(0);
        date.setMilliseconds(milliseconds);

        let hours = date.getUTCHours();
        const minutes = date.getUTCMinutes();

        const ampm = hours >= 12 ? 'PM' : 'AM';
        hours = hours % 12 || 12;

        const minutesStr = minutes.toString().padStart(2, '0');

        return `${hours}:${minutesStr} ${ampm}`;
    }

    formatDateRange(startDate, endDate) {
        const start = new Date(startDate);
        const end = new Date(endDate);

        const startFormatted = this.formatDate(start);
        const endFormatted = this.formatDate(end);

        if (startDate === endDate) {
            return startFormatted;
        } else {
            return `${startFormatted} - ${endFormatted}`;
        }
    }

    formatDate(dateStr) {
        const date = new Date(dateStr);
        const day = date.getDate().toString().padStart(2, '0');
        const year = date.getFullYear().toString();
        return `${day} ${this.formatMonthName(date.getMonth())} ${year}`;
    }

    formatMonthName(monthIndex) {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return months[monthIndex];
    }

    async showModernToast(event) {
        this.toastTitle = event.detail.title;
        this.toastMessage = event.detail.message;
        this.toastVariant = event.detail.variant;
        this.showToast = true;

        if (this.toastTitle == 'Registration Successful!' || this.toastTitle == 'Cancellation Successful!') {
            console.log('Refreshing Registered Sessions');
            await refreshApex(this.wiredRegisteredSessionsData);
            await refreshApex(this.wiredEventSchedulesResult);

            const eventSchedule = this.template.querySelector('c-ken-event-schedule');
            if (eventSchedule) {
                console.log('test');
                eventSchedule.refreshSchedules();
            }
        }
        // Auto hide after 3 seconds
        setTimeout(() => {
            this.hideToast();
        }, 3000);
    }

    hideToast() {
        this.showToast = false;
    }

}