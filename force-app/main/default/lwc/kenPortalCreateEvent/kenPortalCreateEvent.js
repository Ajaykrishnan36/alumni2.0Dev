import { LightningElement, track, wire, api } from 'lwc';
import saveEvent from '@salesforce/apex/KenEventFormController.saveEvent';
import getEvent from '@salesforce/apex/KenEventFormController.getEvent';
import getEventSchedule from '@salesforce/apex/KenEventFormController.getEventSchedule';
import createEventSchedule from '@salesforce/apex/KenEventFormController.createEventSchedule';
import deleteEventSession from '@salesforce/apex/KenEventFormController.deleteEventSession';
import getPicklistValuesByFields from '@salesforce/apex/KenEventFormController.getPicklistValues';
import deleteSessionsData from '@salesforce/apex/KenEventFormController.deleteSessionsData';
import saveFeedbackTriggerSettings from '@salesforce/apex/KenEventFormController.saveFeedbackTriggerSettings';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getAudienceGroupsByIds from '@salesforce/apex/KenAudienceEngineService.getAudienceGroupsByIds';
import getLinkedSegmentation from '@salesforce/apex/KenAudienceJunctionController.getLinkedSegmentation';
import uploadFileToRecord from '@salesforce/apex/KenEventFormController.uploadFileToRecord';
import GENERAL_SANS_FONT from '@salesforce/resourceUrl/GeneralSansFont';
import FORM_FACTOR from '@salesforce/client/formFactor'; 
import updateFee from '@salesforce/apex/KenEventFormController.updateFee';
import getQuestionnaireByEventId from '@salesforce/apex/KenEventFormController.getQuestionnaireByEventId';
import saveQuestionnaireForEvent from '@salesforce/apex/KenEventFormController.saveQuestionnaireForEvent';
import saveQuestionnaireForSession from '@salesforce/apex/KenEventFormController.saveQuestionnaireForSession';
import savePreEventSurveyData from '@salesforce/apex/KenEventFormController.savePreEventSurveyData';
import saveMealFee from '@salesforce/apex/KenEventFormController.saveMealFee';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

// Admin = running inside the Lightning Experience shell (action override / app page),
// whose URLs live under `/lightning/...`. Everything else is an Experience Cloud portal.
// Do NOT detect the portal via `/s/` — that only exists on Aura sites; LWR sites use clean
// URLs, so a `/s/` check misfires and makes the portal look like admin (wrong layout height).
const IS_ADMIN_CONTEXT = (() => {
    try {
        if (typeof window === 'undefined' || !window.location) return false;
        return (window.location.pathname || '').indexOf('/lightning/') !== -1;
    } catch (e) {
        return false;
    }
})();

export default class KenPortalCreateEvent extends NavigationMixin(LightningElement) {
    isMobile = false;
    // True when hosted outside Experience Cloud (System Admin / Lightning app action
    // override). In that host the Salesforce shell already sizes the scroll region, so
    // the 100vh-based layout would push the footer off-screen — toggle an `is-admin` modifier.
    isAdminContext = IS_ADMIN_CONTEXT;

    get containerClass() {
        return this.isAdminContext ? 'component-container is-admin' : 'component-container';
    }

    get pageClass() {
        return this.isAdminContext ? 'mobile-view-container is-admin-page' : 'mobile-view-container';
    }
    @track currentEventId;
    @track isEditMode = false;
    @track showSpinner = false;
    @track accessDenied = false;

    @track isToastVisible = false;
    @track toastTitle = '';
    @track toastMessage = '';
    @track toastVariant = 'success';

    // Step management
    @track currentStep = 1;
    // When the org has Disable_Event_Fee__c enabled, the Fee Setup step (5) is
    // skipped entirely and all fee/total info is hidden from the wizard + summary.
    @track feeDisabled = false;
    @track isStep1Completed = false;
    @track isStep2Completed = false;
    @track isStep3Completed = false;
    @track isStep4Completed = false;
    @track isStep5Completed = false;
    @track isStep6Completed = false;
    @track isStep7Completed = false;
    @track customSurveyEnabled = false;

    // Fee setup
    @track feeRowsByDate = [];
    @track feeSummaryTotal = 0;
    @track pricingMode = null; // 'SESSION_WISE' | 'OVERALL' | null
    @track overallPrice = '';
    @track overallIsFree = false;
    @track mealFees = '';
    @track showFeeSummaryModal = false;
    @track feeSummarySessions = [];

    // Survey setup
    @track surveyMandatory = false;
    @track surveyQuestionnaireId = '';
    @track surveyQuestions = [
        {
            id: 'q-1',
            number: 1,
            text: '',
            type: 'multiple',
            required: false,
            options: [
                { id: 'opt-1', text: '', letter: 'a' },
                { id: 'opt-2', text: '', letter: 'b' }
            ],
            hasOptions: true
        }
    ];
    @track surveyMealsData = {
        mealsPaidAddonEnabled: false
    };

    // Feedback setup
    @track feedbackFormsByDate = [];
    @track showMissingFeedbackModal = false;
    @track showTriggeringFeedbackModal = false;
    @track triggerType = 'auto';
    @track triggerWhen = '';
    @track activeFeedbackSessionId = null;
    @track feedbackDataBySession = {};

    // Multi-select dropdowns
    @track eventCategories = [];
    @track eventLanguages = [];
    @track suitableForData = [];
    @track isPicklistDataLoaded = false;

    @track showCategoryDropdown = false;
    @track showSuitableForDropdown = false;
    @track showLanguageDropdown = false;

    @track selectedCategories = [];
    @track selectedSuitableFor = [];
    @track selectedLanguages = [];
    @track selectedAudienceData = [];
    // Audience seeded from a "Create an Event" launched inside a group — passed down to
    // the target-audience step so the group shows pre-selected on a brand-new event.
    @track preselectedAudience = [];
    _pendingPreselectGroup = null;   // { id, name } captured from URL params
    _groupPreselectConsumed = false; // seed the group audience at most once
    _hasConnected = false;           // gate preselection until after connectedCallback/resetForm

    // Validation errors
    @track validationErrors = {
        title: '',
        category: '',
        maxParticipants: '',
        description: '',
        expectations: '',
        agenda: '',
        suitableFor: '',
        language: '',
        coverPhoto: '',
        selectedDates: '',
        sessionTitle: '',
        timeRange: '',
        sessionAgenda: '',
        speakerName: '',
        locationType: '',
        sessionStartTime: '',
        sessionEndTime: '',
        timeRange: '',
        eventLink: '',
        venueAddress: '',
        brochure: ''
    };

    @track eventData = {
        title: '',
        categories: [],
        maxParticipants: '',
        description: '',
        expectations: '',
        targetAudienceApplicable: [],
        languages: [],
        coverImage: null,
        coverImageFileName: '',
        broucher: null,
        broucherFileName: '',
        agenda: '',
        canBringGuests: 'yes',
        maxGuestsPerParticipant: 1
    };

    // Step 2: Date Selection
    @track currentDate = new Date();
    @track selectedDates = [];
    @track calendarDays = [];

    // Step 3: Schedule Setup
    @track activeDateTab = '';
    @track sessionsByDate = {};
    @track showSessionForm = false;
    @track editingSessionId = null;
    // Holds an in-progress, not-yet-saved new session while the user temporarily
    // expands another (already saved) session, so the new session is not lost.
    pendingNewSession = null;

    @track currentSession = {
        title: '',
        startTime: '',
        endTime: '',
        agenda: '',
        brochure: null,
        brochureFileName: '',
        speakers: [],
        locationType: 'online',
        venueAddress: '',
        eventLink: '',
        noFee: true
    };

    @track currentSessionByDate = {};

    @track currentSpeaker = {
        id: '',
        uniqueId: '',
        name: '',
        email: '',
        sendInvite: false,
        image: null,
        imageFileName: '',
        description: ''
    };

    @track showSpeakerForm = false;
    @track editingSpeakerId = null;
    @track wiredEventScheduleResponse = null;
    //
    @track sendEmail = false;
    @track emailSubject = '';
    @track emailDistributionList = [];
    @track emailDistributionOptions = [
        { key: 'student', label: 'Student', value: 'Student', selected: false },
        { key: 'faculty', label: 'Faculty', value: 'Faculty', selected: false },
        { key: 'staff', label: 'Staff', value: 'Staff', selected: false }
    ];
    @track selectedEmailDistributionList = [];
    @track showEmailDistributionDropdown = false;
    @track showCancelConfirmModal = false;
    @track showEmailConfirmModal = false;
    @track showShareEmailModal = false;
    //email fields
    @track shareEmailSubject = '';
    @track emailBody = '';
    @track scheduleDate = '';
    @track scheduleTime = '';
    @track emailAttachment = null;
    _recordId;
    _surveyLoadedForEventId;
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && value !== this.currentEventId) {
            this.currentEventId = value;
            this.isEditMode = true;
        }
    }
    @track selectedFileName = '';
    @track minDate = '';
    subjectError = '';
    bodyError = '';
    handleEmailDistributionDropdownToggle(event) {
        event.stopPropagation();
        this.showEmailDistributionDropdown = !this.showEmailDistributionDropdown;
        console.log('Dropdown toggled. Now showEmailDistributionDropdown =', this.showEmailDistributionDropdown);
    }
    handleClickOutside = (event) => {
        if (!this.showEmailDistributionDropdown) {
            return;
        }

        const dropdownContainer = this.template.querySelector('.multi-select-container');

        if (dropdownContainer && !dropdownContainer.contains(event.target)) {
            console.log('➡️ Outside click detected → closing dropdown');
            this.showEmailDistributionDropdown = false;
        } else {
            console.log('✅ Click inside dropdown → keep it open');
        }
    };





    connectedCallback() {
        // Block portal users from reaching /host-event directly when hosting is
        // disabled in the org's custom setting. Backend/internal users are never gated.
        this.enforcePortalHostEventAccess();

        // Store bound versions of methods in separate properties
        this.boundHandleGlobalClick = this.handleGlobalClick.bind(this);
        this.boundHandleKeyDown = this.handleKeyDown.bind(this);
    
        // Add event listeners
        window.addEventListener('click', this.boundHandleGlobalClick);
        window.addEventListener('keydown', this.boundHandleKeyDown);
    
        const today = new Date();
        const yyyy = today.getFullYear();
        const mm = String(today.getMonth() + 1).padStart(2, '0'); // month is 0-based
        const dd = String(today.getDate()).padStart(2, '0');
        this.minDate = `${yyyy}-${mm}-${dd}`;
    
        window.addEventListener('click', this.handleClickOutside);
        console.log('✅ Added document click listener for outside clicks');
    
        this.isMobile = FORM_FACTOR === 'Small';
    
        if (typeof document !== 'undefined' && document.head && !document.getElementById('general-sans-fonts')) {
            const regularFontUrl = `${GENERAL_SANS_FONT}/fonts/GeneralSans-Regular.woff2`;
            const boldFontUrl = `${GENERAL_SANS_FONT}/fonts/GeneralSans-Light.woff2`;
            const style = document.createElement('style');
            style.id = 'general-sans-fonts';
            style.innerText = `
                @font-face {
                    font-family: 'GeneralSansCustom';
                    src: url('${regularFontUrl}') format('woff2');
                    font-style: normal;
                    font-display: swap;
                }
        
                @font-face {
                    font-family: 'GeneralSansCustomBold';
                    src: url('${boldFontUrl}') format('woff2');
                    font-style: normal;
                    font-display: swap;
                }
            `;
            document.head.appendChild(style);
        }
    
        // A ?preselectGroupId=… in the URL means "start a FRESH event pre-filled with
        // this group" — never resume a stale in-progress draft in that case.
        const preselectGroupId = this.readPreselectGroupIdFromUrl();
        if (preselectGroupId) {
            try { sessionStorage.removeItem('currentEventId'); } catch (e) { /* ignore */ }
            this._pendingPreselectGroup = { id: preselectGroupId };
        }

        const cachedId = sessionStorage.getItem('currentEventId');
        if (cachedId) {
            console.log('cachedId', cachedId);
            this.currentEventId = cachedId;
            this.isEditMode = true;
        }

        if (this._recordId && this._recordId !== this.currentEventId) {
            this.currentEventId = this._recordId;
            this.isEditMode = true;
        }

        // Fresh "Host Event" entry: no in-progress draft (cachedId) and not editing an existing event
        // (_recordId). Clear any stale state left in this reused component instance from a previously
        // completed event so Portal AND Admin both show an empty form instead of the last event's data.
        if (!cachedId && !this._recordId) {
            this.resetForm();
        }
        // Fresh event launched from a group's "Create an Event" pre-selects that group
        // as the target audience — applied here (after resetForm) or from the page-ref
        // wire, whichever settles last.
        this._hasConnected = true;
        this.maybeApplyPreselectedGroup();
        console.log('test0');
        this.getPicklistOptions();
        this.generateCalendar();
        if (this.selectedDates.length > 0) {
            this.activeDateTab = this.selectedDates[0].key;
        }
    
        this.boundHandleWindowResize = this.handleWindowResize.bind(this);
    
        // Add window resize listener
        window.addEventListener('resize', this.boundHandleWindowResize);
    
        this.validationErrors = {
            sessionTitle: '',
            sessionStartTime: '',
            sessionEndTime: '',
            timeRange: '',
            sessionAgenda: '',
            locationType: '',
            eventLink: '',
            sessionBrochure: '',
            venueAddress: ''
        };
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
            this.feeDisabled = color?.disableEventFee === true;
        }).catch(() => {
            document.documentElement.style.setProperty('--primary-color', '#B7202E');
            document.documentElement.style.setProperty('--secondary-color', '#E9BABE');
            document.documentElement.style.setProperty('--tertiary-color', '#F8E9EA');
        });
    }


    handleEmailDistributionSelect(event) {
        event.stopPropagation(); // stop closing immediately when selecting

        const value = event.currentTarget.dataset.value;
        const option = this.emailDistributionOptions.find(opt => opt.value === value);

        if (option) {
            option.selected = !option.selected;

            if (option.selected) {
                if (!this.selectedEmailDistributionList.some(item => item.value === value)) {
                    this.selectedEmailDistributionList = [
                        ...this.selectedEmailDistributionList,
                        { key: option.key, label: option.label, value: option.value }
                    ];
                }
            } else {
                this.selectedEmailDistributionList = this.selectedEmailDistributionList.filter(
                    item => item.value !== value
                );
            }

            this.emailDistributionList = this.selectedEmailDistributionList.map(item => item.value);
        }
    }

    handleRemoveEmailDistribution(event) {
        event.stopPropagation(); // prevent dropdown from closing immediately

        const value = event.currentTarget.dataset.value;

        this.selectedEmailDistributionList = this.selectedEmailDistributionList.filter(
            item => item.value !== value
        );

        const option = this.emailDistributionOptions.find(opt => opt.value === value);
        if (option) option.selected = false;

        this.emailDistributionList = this.selectedEmailDistributionList.map(item => item.value);
    }

    // Computed properties for step classes
    get isStep1Active() {
        return this.currentStep === 1;
    }

    get isStep2Active() {
        return this.currentStep === 2;
    }

    get isStep3Active() {
        return this.currentStep === 3;
    }

    get isStep4Active() {
        return this.currentStep === 4;
    }

    get isStep5Active() {
        return this.currentStep === 5;
    }

    get isStep6Active() {
        return this.currentStep === 6;
    }

    get isStep7Active() {
        return this.currentStep === 7;
    }

    get stepperItems() {
        const steps = [
            { number: 1, label: 'Event Setup', completed: this.isStep1Completed },
            { number: 2, label: 'Target Audience', completed: this.isStep2Completed },
            { number: 3, label: 'Schedule Setup', completed: this.isStep3Completed },
            { number: 4, label: 'Pre Event Surveys', completed: this.isStep4Completed },
            { number: 5, label: 'Fee Setup', completed: this.isStep5Completed },
            { number: 6, label: 'Feedback Form', completed: this.isStep6Completed },
            { number: 7, label: 'Summary', completed: this.isStep7Completed }
        ];

        const totalSteps = steps.length;

        return steps.map(step => {
            const isActive = this.currentStep === step.number;
            const isCompleted = step.completed || this.currentStep > step.number;
            return {
                ...step,
                isActive,
                isCompleted,
                isLast: step.number === totalSteps,
                statusClass: `step ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''}`.trim(),
                lineClass: isCompleted ? 'step-line completed' : 'step-line'
            };
        });
    }

    get stepIndicatorLabel() {
        return `Step ${this.currentStep} out of 7`;
    }

    get progressFillStyle() {
        const progress = Math.min(100, ((this.currentStep - 1) / 6) * 100);
        return `width:${progress}%`;
    }

    // Seed data for the Pre Event Surveys step (edit-mode resume)
    get surveyInitialData() {
        return {
            offerMealsEnabled: this.surveyMealsData?.offerMealsEnabled,
            mealsByDate: this.surveyMealsData?.mealsByDate,
            mealsPaidAddonEnabled: this.surveyMealsData?.mealsPaidAddonEnabled,
            dietaryEnabled: this.surveyMealsData?.dietaryEnabled,
            dietaryOptions: this.surveyMealsData?.dietaryOptions,
            customSurveyEnabled: this.customSurveyEnabled,
            surveyQuestions: this.surveyQuestions
        };
    }

    // Assembled data for the Summary step (step 7)
    get eventSummaryData() {
        const formatMoney = (n) => `₹${(Number(n) || 0).toFixed(2)}`;

        // Audience groups (defensive about the shape emitted by the target-audience step)
        let audienceGroups = (this.selectedAudienceData || []).map((a, i) => {
            const name = a.name || a.label || a.title || a.groupName || `Group ${i + 1}`;
            const type = a.type || a.category || a.audienceType || a.segmentType ||
                (Array.isArray(a.types) ? a.types.join(', ') : '') || '';
            const count = a.memberCount ?? a.count ?? a.members ?? a.totalMembers ?? a.size;
            const memberLabel = (count !== undefined && count !== null && count !== '') ? `${count} Members` : '';
            return { key: a.id || a.Id || `grp-${i}`, name, type, memberLabel };
        });
        if (!audienceGroups.length && (this.selectedSuitableFor || []).length) {
            audienceGroups = [{
                key: 'aud-0',
                name: 'Target Audience',
                type: this.selectedSuitableFor.map(s => s.label).join(', '),
                memberLabel: ''
            }];
        }

        // Meal lines from the pre-event survey
        const mealsByDate = this.surveyMealsData?.mealsByDate || {};
        const mealLines = Object.keys(mealsByDate).map(dateKey => {
            const dateObj = (this.selectedDates || []).find(d => (d.value || d.key) === dateKey);
            return {
                key: dateKey,
                date: dateObj ? dateObj.display : dateKey,
                meals: (mealsByDate[dateKey] || []).join(', ')
            };
        });

        // Feedback question counts by session
        const feedbackCountBySession = {};
        (this.feedbackFormsByDate || []).forEach(day => {
            (day.sessions || []).forEach(s => {
                feedbackCountBySession[s.uniqueId] = s.questionsCount || (s.questions ? s.questions.length : 0);
            });
        });

        // Session details
        const sessionDays = (this.feeRowsByDate || []).map(row => {
            const sessions = (row.sessions || []).map((s, idx) => {
                const count = feedbackCountBySession[s.uniqueId] || 0;
                return {
                    key: s.uniqueId || `${row.dateKey}-${idx}`,
                    sessionLabel: `Session ${idx + 1}`,
                    title: s.title || '',
                    price: s.isFree ? '₹-' : (s.price !== '' && s.price != null ? formatMoney(s.price) : '₹-'),
                    feedback: count ? `${count} Questions` : '-'
                };
            });
            return { key: row.dateKey, date: row.displayDate, sessions };
        });

        // Totals
        let base = 0;
        if (this.pricingMode === 'OVERALL') {
            base = this.overallIsFree ? 0 : (Number(this.overallPrice) || 0);
        } else {
            base = Number(this.feeSummaryTotal) || 0;
        }
        const showMealFee = !!this.surveyMealsData?.mealsPaidAddonEnabled &&
            this.mealFees !== '' && this.mealFees != null;
        const mealFee = showMealFee ? (Number(this.mealFees) || 0) : 0;
        const total = base + mealFee;

        return {
            eventTitle: this.eventData.title || '',
            category: (this.selectedCategories || []).map(c => c.label).join(', '),
            language: (this.selectedLanguages || []).map(l => l.label).join(', '),
            brochureFileName: this.eventData.broucherFileName || 'Brochure',
            hasBrochure: !!(this.eventData.brochure || this.eventData.broucherFileName),
            audienceGroups,
            dates: (this.selectedDates || []).map(d => ({ key: d.key || d.value, display: d.display })),
            mealLines,
            customSurveyCount: this.customSurveyEnabled ? (this.surveyQuestions ? this.surveyQuestions.length : 0) : 0,
            sessionDays,
            showMealFee: showMealFee && !this.feeDisabled,
            mealFeeDisplay: formatMoney(mealFee),
            totalDisplay: formatMoney(total),
            feeDisabled: this.feeDisabled
        };
    }

    get currentMonthYear() {
        return this.currentDate.toLocaleDateString('en-US', {
            month: 'long',
            year: 'numeric'
        });
    }

    getDateTabClass(dateKey) {
        const isActive = dateKey === this.activeDateTab;
        return isActive ? 'date-tab active' : 'date-tab';
    }

    get calendarDayClasses() {
        return 'calendar-day';
    }

    get canProceed() {
        if (this.currentStep === 3) {
            return Object.keys(this.sessionsByDate).length > 0 &&
                Object.values(this.sessionsByDate).every(dateSessions =>
                    dateSessions.sessions && dateSessions.sessions.length > 0
                );
        }
        return true;
    }

    get isStep3ProceedDisabled() {
        if (this.currentStep !== 3) return false;
        return this.hasAnyInvalidSession;
    }

    get hasAnyInvalidSession() {
        const dates = Object.keys(this.sessionsByDate || {});
        if (!dates.length) return true;
        const editId = this.currentSession?.uniqueId;
        for (const dk of dates) {
            const sessions = this.sessionsByDate[dk].sessions || [];
            if (!sessions.length) return true;
            for (const s of sessions) {
                const eff = (editId && s.uniqueId === editId) ? this.currentSession : s;
                if (!eff.title || !eff.title.trim()) return true;
                if (!eff.startTime || !eff.endTime) return true;
                if (!(eff.agenda || '').trim()) return true;
                if (!eff.locationType) return true;
                if (this.timeToMinutes(eff.endTime) <= this.timeToMinutes(eff.startTime)) return true;
                if (this._locationInvalid(eff)) return true;
            }
        }
        return false;
    }

    get showVenueAddress() {
        return this.currentSession.locationType === 'onsite' ||
            this.currentSession.locationType === 'hybrid';
    }

    get showEventLink() {
        return this.currentSession.locationType === 'online' ||
            this.currentSession.locationType === 'hybrid';
    }

    get surveyTypeOptions() {
        return [
            { label: 'Single Select', value: 'multiple' },
            { label: 'Checkbox', value: 'checkbox' },
            { label: 'Linear scale', value: 'linear' },
            { label: 'Short answer', value: 'text' }
        ];
    }

    get currentSessionForActiveDate() {
        if (!this.activeDateTab) return this.currentSession;

        if (!this.currentSessionByDate[this.activeDateTab]) {
            this.currentSessionByDate[this.activeDateTab] = {
                id: '',
                title: '',
                startTime: '',
                endTime: '',
                agenda: '',
                brochure: null,
                speakers: [],
                locationType: 'online',
                venueAddress: '',
                eventLink: ''
            };
        }
        return this.currentSessionByDate[this.activeDateTab];
    }

    get currentDateSessions() {
        const sessions = this.sessionsByDate[this.activeDateTab] || { sessions: [] };
        return {
            ...sessions,
            sessions: sessions.sessions.map((session, index) => ({
                ...session,
                displayNumber: index + 1,
                isEditing: this.editingSessionId === session?.uniqueId,
                isExpanded: session.isExpanded !== undefined ? session.isExpanded : false,
                speakers: (session.speakers || []).map((speaker, speakerIndex) => ({
                    ...speaker,
                    displayNumber: speakerIndex + 1,
                    isEditing: this.editingSpeakerId === speaker?.uniqueId
                }))
            }))
        };
    }

    get showSessionsList() {
        return this.currentDateSessions.sessions && this.currentDateSessions.sessions.length > 0;
    }

    get showAddSessionButton() {
        return this.showSessionsList && !this.showSessionForm && !this.editingSessionId;
    }

    get showInitialSessionForm() {
        return !this.showSessionsList && !this.showSessionForm;
    }

    get isOnlineSelected() {
        return this.currentSession.locationType === 'online';
    }

    get isOnsiteSelected() {
        return this.currentSession.locationType === 'onsite';
    }

    get isHybridSelected() {
        return this.currentSession.locationType === 'hybrid';
    }

    get showSpeakersList() {
        return this.currentSession.speakers && this.currentSession.speakers.length > 0;
    }

    get showAddSpeakerButton() {
        return this.showSpeakersList && !this.showSpeakerForm && !this.editingSpeakerId;
    }

    get currentSessionSpeakers() {
        return (this.currentSession.speakers || []).map((speaker, index) => ({
            ...speaker,
            displayNumber: index + 1,
            isEditing: this.editingSpeakerId === speaker.uniqueId
        }));
    }

    get shouldShowSpeakerForm() {
        return (this.currentSession && this.currentSession.speakers && this.currentSession.speakers.length === 0) || this.showSpeakerForm;
    }

    get shouldShowSessionForm() {
        // Only show form when actively adding (showSessionForm) or editing (editingSessionId)
        // Do NOT show when in empty state (no sessions and not adding)
        return this.showSessionForm || this.editingSessionId !== null;
    }

    get sessionBrochureClass() {
        return this.validationErrors.sessionBrochure ? 'form-control error' : 'form-control';
    }

    get fileSizeFormatted() {
        if (!this.currentSession.brochure) return '';

        const base64Length = this.currentSession.brochure.length;
        const sizeInBytes = (base64Length * 3) / 4;

        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        if (sizeInBytes === 0) return '0 Byte';

        const i = parseInt(Math.floor(Math.log(sizeInBytes) / Math.log(1024)));
        return Math.round(sizeInBytes / Math.pow(1024, i) * 100) / 100 + ' ' + sizes[i];
    }

    get dateTabsWithClasses() {
        return this.selectedDates.map(date => ({
            key: date.key,
            display: date.display,
            classes: date.key === this.activeDateTab ? 'date-tab active' : 'date-tab'
        }));
    }

    // Get event session dates for Survey Setup (Step 4)
    get eventSessionDates() {
        // IMPORTANT: Step 4 should reflect the dates selected in Step 1/2 (Event Session Dates),
        // not only dates that already have sessions in Step 3.
        // Step 3 tabs already use `selectedDates`, so we mirror that source of truth here.

        const selected = Array.isArray(this.selectedDates) ? this.selectedDates : [];

        // Normalize to ISO date (YYYY-MM-DD), distinct, sorted ASC
        const isoDates = [...new Set(selected.map(d => {
            const raw = d?.value || d?.key || d;
            return typeof raw === 'string' ? raw.split('T')[0] : raw;
        }).filter(Boolean))].sort();

        return isoDates.map(dateISO => {
            const match = selected.find(d => {
                const raw = d?.value || d?.key || d;
                const iso = typeof raw === 'string' ? raw.split('T')[0] : raw;
                return iso === dateISO;
            });

            return {
                key: dateISO,
                value: dateISO,
                // Keep the same label used by Step 3 tabs (if available)
                display: match?.display || dateISO
            };
        });
    }

    get submitDisabled() {
        return !this.canProceed;
    }

    get progressFillClass() {
        let progressClass;
        switch (this.currentStep) {
            case 1:
                progressClass = 'progress-14';
                break;
            case 2:
                progressClass = 'progress-28';
                break;
            case 3:
                progressClass = 'progress-42';
                break;
            case 4:
                progressClass = 'progress-57';
                break;
            case 5:
                progressClass = 'progress-100';
                break;
            default:
                progressClass = 'progress-14';
        }
        return `progress-fill ${progressClass}`;
    }

    async getPicklistOptions() {
        try {
            const picklistData = await getPicklistValuesByFields({
                objectName: 'Ken_Event_Master__c',
                fieldNames: ['Event_Type__c', 'Language__c', 'Target_Audience_Applicable__c']
            });

            if (!picklistData) {
                this.showToast('Error', 'Error fetching picklist values', 'error');
                return;
            }

            this.eventLanguages = this.formatPicklistValues(picklistData.Language__c, this.selectedLanguages);
            this.eventCategories = this.formatPicklistValues(picklistData.Event_Type__c, this.selectedCategories);
            this.suitableForData = this.formatPicklistValues(picklistData.Target_Audience_Applicable__c, this.selectedSuitableFor);

            this.isPicklistDataLoaded = true;
        } catch (error) {
            console.error('Error loading picklist data:', error);
            this.showToast('Error', 'Failed to load form options', 'error');
            this.isPicklistDataLoaded = true;
        }
    }

    formatPicklistValues(picklistOptions, selectedValues) {
        if (!Array.isArray(picklistOptions)) {
            return [];
        }

        const selectedValuesArray = selectedValues.map(item =>
            typeof item === 'object' ? item.value : item
        );

        return picklistOptions?.map(option => ({
            key: option.value,
            label: option.label,
            value: option.value,
            show: true,
            selected: selectedValuesArray.includes(option.value)
        }));
    }

    // Multi-select options
    get categoryOptions() {
        return this.eventCategories || [];
    }

    get languageOptions() {
        return this.eventLanguages || [];
    }

    get suitableForOptions() {
        return this.suitableForData || [];
    }

    get hasCoverPhoto() {
        return this.eventData.coverImage !== null && this.eventData.coverImageFileName !== '';
    }

    get hasBrochureFile() {
        return this.eventData.brochure !== null && this.eventData.broucherFileName !== '';
    }

    get descriptionValue() {
        return this.eventData.description || '';
    }

    // get expectationsValue() {
    //     return this.eventData.expectations || '';
    // }

    get agendaValue() {
        return this.eventData.agenda || '';
    }

    // Validation computed properties
    get isStep1Invalid() {
        // Required fields: title, category, coverPhoto, canBringGuests, selectedDates
        const hasTitle = this.eventData.title && this.eventData.title.trim() !== '';
        const hasExpectations = this.eventData.expectations && this.eventData.expectations.trim() !== '';
        const hasCategory = this.selectedCategories.length > 0;
        const hasCoverPhoto = !!this.eventData.coverImage;
        const hasCanBringGuests = !!this.eventData.canBringGuests;
        const hasSelectedDates = this.selectedDates.length > 0;
        
        // Conditionally required: maxGuestsPerParticipant (only if canBringGuests === 'yes')
        const needsMaxGuests = this.eventData.canBringGuests === 'yes';
        const hasMaxGuests = !needsMaxGuests || (this.eventData.maxGuestsPerParticipant !== undefined && this.eventData.maxGuestsPerParticipant !== null && this.eventData.maxGuestsPerParticipant > 0);
        
        return !hasTitle || !hasExpectations || !hasCategory || !hasCoverPhoto || !hasCanBringGuests || !hasSelectedDates || !hasMaxGuests;
    }

    get hasTargetAudienceSelection() {
        const hasAudience = Array.isArray(this.selectedAudienceData) && this.selectedAudienceData.length > 0;
        const hasLegacy = Array.isArray(this.selectedSuitableFor) && this.selectedSuitableFor.length > 0;
        return hasAudience || hasLegacy;
    }

    get isStep2Invalid() {
        return !this.hasTargetAudienceSelection;
    }

    get isStep3Invalid() {
        if (!Array.isArray(this.selectedDates) || this.selectedDates.length === 0) {
            return true;
        }
        const allDatesHaveSessions = this.selectedDates.every(date => {
            const sessions = this.sessionsByDate[date.key];
            return sessions && sessions.sessions && sessions.sessions.length > 0;
        });

        return !allDatesHaveSessions;
    }

    // Error state classes
    get eventTitleClass() {
        return this.validationErrors.title ? 'form-control error' : 'form-control';
    }

    get maxParticipantsClass() {
        return this.validationErrors.maxParticipants ? 'form-control error' : 'form-control';
    }

    get descriptionClass() {
        return this.validationErrors.description ? 'form-control error' : 'form-control';
    }

    // get expectationsClass() {
    //     return this.validationErrors.expectations ? 'form-control error' : 'form-control';
    // }

    get agendaClass() {
        return this.validationErrors.agenda ? 'form-control error' : 'form-control';
    }

    get timeRangeError() {
        return this.validationErrors.timeRange ||
            this.validationErrors.sessionStartTime ||
            this.validationErrors.sessionEndTime ||
            '';
    }

    get sessionTitleClass() {
        return this.validationErrors.sessionTitle ? 'form-control error' : 'form-control';
    }

    get sessionAgendaClass() {
        return this.validationErrors.sessionAgenda ? 'form-control error' : 'form-control';
    }

    get speakerNameClass() {
        return this.validationErrors.speakerName ? 'form-control error' : 'form-control';
    }



    // async connectedCallback() {

    // }

    /**
     * Gate the Host-an-Event page for PORTAL users only.
     * In internal/backend Lightning, @salesforce/community/basePath is empty, so
     * admins are never blocked. For portal users, if Allow Create Events
     * (Alumni_Module_Settings__c) is not enabled for the org, deny access and
     * redirect to the Events page so a user
     * cannot reach /host-event directly while the Host Event card is hidden.
     */
    /**
     * Community base path derived from the URL, with no dependency on the
     * community-only scoped module (which breaks the backend action override).
     * Returns '' in the internal Lightning app (runs under /lightning/*), and
     * the leading site segment (e.g. '/alumni') in an Experience site.
     */
    get cBasePath() {
        try {
            const path = (typeof window !== 'undefined' && window.location && window.location.pathname)
                ? window.location.pathname : '';
            if (!path || path.indexOf('/lightning/') !== -1) {
                return '';
            }
            const seg = path.split('/').filter((s) => s);
            return seg.length ? '/' + seg[0] : '';
        } catch (e) {
            return '';
        }
    }

    enforcePortalHostEventAccess() {
        const isPortal = !!this.cBasePath;
        if (!isPortal) {
            return; // backend/internal user — always allowed
        }
        getPrimaryColor()
            .then((config) => {
                if (config && config.showHostEvent === true) {
                    return; // hosting enabled for this org — allowed
                }
                this.denyPortalAccess();
            })
            .catch(() => {
                // Could not confirm the setting — fail safe by denying on the portal
                this.denyPortalAccess();
            });
    }

    denyPortalAccess() {
        this.accessDenied = true;
        const base = (this.cBasePath || '').replace(/\/+$/, '');
        // Redirect immediately to the portal Events page.
        window.location.assign(`${base}/event`);
    }

    disconnectedCallback() {
        window.removeEventListener('click', this.boundHandleGlobalClick);

        // Remove window resize listener
        window.removeEventListener('click', this.handleClickOutside);
        console.log('❌ Removed document click listener');

        window.removeEventListener('resize', this.handleWindowResize);

        // The Experience Cloud SPA router doesn't always tear down and recreate this
        // component when navigating away and back to the host_event__c route (e.g.
        // Save as Draft or completing an event, then starting a new one) — connectedCallback's
        // own reset gate can be skipped if the same instance is reused. Reset here too so a
        // reused instance never shows the previous event's data on the next "Host Event" entry.
        try {
            this.resetForm();
        } catch (e) {
            console.error('Error resetting form on disconnect:', e);
        }
    }

    showToast(title, message, variant) {
        this.toastTitle = title;
        this.toastMessage = message;
        this.toastVariant = variant;
        this.isToastVisible = true;

        setTimeout(() => {
            this.isToastVisible = false;
        }, 3000);
    }

    get toastClasses() {
        return `modern-toast ${this.toastVariant}`;
    }

    get toastIcon() {
        switch (this.toastVariant) {
            case 'success':
                return 'M10.95 15.95L16.2375 10.6625L15.1875 9.6125L10.95 13.85L8.8125 11.7125L7.7625 12.7625L10.95 15.95ZM12 20C10.9625 20 9.9875 19.803 9.075 19.409C8.1625 19.0155 7.36875 18.4813 6.69375 17.8063C6.01875 17.1313 5.4845 16.3375 5.091 15.425C4.697 14.5125 4.5 13.5375 4.5 12.5C4.5 11.4625 4.697 10.4875 5.091 9.575C5.4845 8.6625 6.01875 7.86875 6.69375 7.19375C7.36875 6.51875 8.1625 5.98425 9.075 5.59025C9.9875 5.19675 10.9625 5 12 5C13.0375 5 14.0125 5.19675 14.925 5.59025C15.8375 5.98425 16.6313 6.51875 17.3063 7.19375C17.9813 7.86875 18.5155 8.6625 18.909 9.575C19.303 10.4875 19.5 11.4625 19.5 12.5C19.5 13.5375 19.303 14.5125 18.909 15.425C18.5155 16.3375 17.9813 17.1313 17.3063 17.8063C16.6313 18.4813 15.8375 19.0155 14.925 19.409C14.0125 19.803 13.0375 20 12 20Z';
            case 'error':
            default:
                return 'M12 2C6.48 2 2 6.48 2 12C2 17.52 6.48 22 12 22C17.52 22 22 17.52 22 12C22 6.48 17.52 2 12 2ZM13 17H11V15H13V17ZM13 13H11V7H13V13Z';
        }
    }

    @wire(getEvent, { recordId: '$currentEventId' })
    wiredEvent({ error, data }) {
        if (!this.currentEventId) return;
        if (data) {
            this.populateFormWithEventData(data);
        } else if (error) {
            console.error('Error loading event:', error);
            this.showToast('Error', 'Failed to load event data', 'error');
        }
    }

    @wire(getEventSchedule, { recordId: '$currentEventId' })
    wiredEventSchedule(response) {
        if (!this.currentEventId) return;
        this.wiredEventScheduleResponse = response;
        const { error, data } = response;
        if (data) {
            this.processEventScheduleData(data);
        } else if (error) {
            console.error('Error loading event schedule:', error);
            this.showToast('Error', 'Failed to load event schedule data', 'error');
        }

    }

    populateFormWithEventData(eventData) {
        this.eventData.title = eventData.eventTitle || '';
        this.eventData.description = eventData.description || '';
        this.eventData.expectations = eventData.eventExpectations || '';
        this.eventData.maxParticipants = eventData.maximumNumberOfParticipants?.toString() || '';
        this.eventData.agenda = eventData.agenda || eventData.targetKeywords || '';
        if (eventData.canAlumniBringGuests !== undefined && eventData.canAlumniBringGuests !== null) {
            this.eventData.canBringGuests = eventData.canAlumniBringGuests ? 'yes' : 'no';
        }
        if (eventData.guestCount !== undefined && eventData.guestCount !== null) {
            this.eventData.maxGuestsPerParticipant = parseInt(eventData.guestCount, 10) || 0;
        }

        if (eventData.image) {
            this.eventData.coverImage = eventData.image;
            this.eventData.coverImageFileName = eventData.imageFileName || 'EventBanner.jpg';
        }
        if (eventData.broucher) {
            this.eventData.brochure = eventData.broucher;
            this.eventData.broucherFileName = eventData.broucherFileName || 'EventBroucher.pdf';
        }

        if (eventData.eventTypes) {
            const categoryValues = eventData.eventTypes?.split(';');
            this.selectedCategories = categoryValues.map(value => {
                const option = this.eventCategories.find(cat => cat.value === value);
                return {
                    key: value,
                    value: value,
                    label: option ? option.label : value
                };
            });

            this.eventCategories.forEach(option => {
                option.selected = categoryValues.includes(option.value);
            });
        }

        if (eventData.eventLanguages) {
            const languageValues = eventData.eventLanguages.split(';');
            this.selectedLanguages = languageValues.map(value => {
                const option = this.eventLanguages.find(lang => lang.value === value);
                return {
                    key: value,
                    value: value,
                    label: option ? option.label : value
                };
            });

            this.eventLanguages.forEach(option => {
                option.selected = languageValues.includes(option.value);
            });
        }

        if (eventData.targetAudienceApplicable) {
            const audienceValues = eventData.targetAudienceApplicable.split(';');
            this.selectedSuitableFor = audienceValues.map(value => {
                const option = this.suitableForData.find(item => item.value === value);
                return {
                    key: value,
                    value: value,
                    label: option ? option.label : value
                };
            });

            this.suitableForData.forEach(option => {
                option.selected = audienceValues.includes(option.value);
            });
        }

        // Pre Event Survey: meals / dietary flags + meal fee (questions load via loadSurveyIfNeeded;
        // the per-date meal grid is rebuilt from sessions in processEventScheduleData)
        this.surveyMealsData = {
            ...this.surveyMealsData,
            offerMealsEnabled: !!eventData.offerMeals,
            mealsPaidAddonEnabled: !!eventData.makeMealsPaid,
            dietaryEnabled: !!eventData.collectDietary,
            dietaryOptions: eventData.dietaryPreferences
                ? eventData.dietaryPreferences.split(';').filter(Boolean)
                : []
        };
        if (eventData.mealFee !== undefined && eventData.mealFee !== null) {
            this.mealFees = String(eventData.mealFee);
        }

        if (eventData.currentStep && !isNaN(eventData.currentStep) && parseInt(eventData.currentStep, 10) > 1) {
            this.currentStep = parseInt(eventData.currentStep, 10);
        }

        this.isEditMode = true;
        this.eventData = { ...this.eventData };
    }

    processEventScheduleData(sessionsData) {
        if (sessionsData && sessionsData.length > 0) {
            const sessionDates = new Set();
            const sessionsByDateMap = {};
            const mealsByDateAcc = {};
            const feedbackBySession = { ...this.feedbackDataBySession };

            sessionsData.forEach(sessionWrapper => {
                if (sessionWrapper.startDate) {
                    const dateStr = this.formatDateToString(new Date(sessionWrapper.startDate));
                    sessionDates.add(dateStr);

                    if (!sessionsByDateMap[dateStr]) {
                        sessionsByDateMap[dateStr] = { sessions: [] };
                    }

                    const session = {
                        id: sessionWrapper.Id || '',
                        uniqueId: sessionWrapper.Id || Date.now().toString(),
                        key: sessionWrapper.Id || Date.now().toString(),
                        title: sessionWrapper.name || '',
                        isExpanded: false,
                        startTime: this.formatTimeFromApex(sessionWrapper.startTime),
                        endTime: this.formatTimeFromApex(sessionWrapper.endTime),
                        timeRange: `${this.formatTimeDisplay(sessionWrapper.startTime)} - ${this.formatTimeDisplay(sessionWrapper.endTime)}`,
                        agenda: sessionWrapper.agenda || '',
                        brochure: sessionWrapper.sessionBroucher || null,
                        brochureFileName: sessionWrapper.brochureFileName || '',
                        brochureFileType: sessionWrapper.broucherFileType || '',
                        locationType: sessionWrapper.locationType || 'online',
                        venueAddress: sessionWrapper.locationAddress || '',
                        eventLink: sessionWrapper.sessionLink || '',
                        sessionFee: sessionWrapper.sessionFee || 0,
                        noFee: sessionWrapper.noFee || false,
                        speakers: this.convertSpeakersFromApex(sessionWrapper.speakers || [])
                    };

                    const mappedTriggerType = this.mapFeedbackTriggerTypeFromDb(sessionWrapper.feedbackTriggerType);
                    const mappedTriggerWhen = this.mapFeedbackTriggerWhenFromDb(sessionWrapper.feedbackTriggerWhen);
                    const mappedEndDate = sessionWrapper.feedbackEndDate
                        ? this.formatDateToString(new Date(sessionWrapper.feedbackEndDate))
                        : '';
                    const mappedEndTime = this.formatTimeFromApex(sessionWrapper.feedbackEndTime);
                    const existingFeedback = feedbackBySession[session.uniqueId] || {};
                    const loadedFeedbackQuestions = this.buildQuestionsFromParams(sessionWrapper.questionnaireParams);
                    feedbackBySession[session.uniqueId] = {
                        ...existingFeedback,
                        questionnaireId: sessionWrapper.questionnaireId || existingFeedback.questionnaireId || null,
                        triggerType: mappedTriggerType || existingFeedback.triggerType || 'auto',
                        triggerWhen: mappedTriggerWhen || existingFeedback.triggerWhen || '',
                        endDate: mappedEndDate || existingFeedback.endDate || '',
                        endTime: mappedEndTime || existingFeedback.endTime || '',
                        questions: (loadedFeedbackQuestions && loadedFeedbackQuestions.length)
                            ? loadedFeedbackQuestions
                            : (existingFeedback.questions || [])
                    };

                    sessionsByDateMap[dateStr].sessions.push(session);

                    if (sessionWrapper.meals) {
                        const meals = sessionWrapper.meals.split(';').filter(Boolean);
                        const existingMeals = mealsByDateAcc[dateStr] || [];
                        mealsByDateAcc[dateStr] = Array.from(new Set([...existingMeals, ...meals]));
                    }
                }
            });

            if (this.currentStep != 3) {
                this.selectedDates = Array.from(sessionDates).map(dateStr => ({
                    key: dateStr,
                    value: dateStr,
                    display: this.formatDateForDisplay(new Date(dateStr))
                }));

                if (this.selectedDates.length > 0) {
                    this.activeDateTab = this.selectedDates[0].key;
                }

                this.generateCalendar();

                if (this.selectedDates.length > 0) {
                    this.isStep1Completed = true;
                    this.isStep2Completed = true;
                    this.currentStep = 3;
                } else {
                    this.isStep1Completed = true;
                    this.currentStep = 2;
                }
            }

            this.feedbackDataBySession = feedbackBySession;
            this.sessionsByDate = sessionsByDateMap;
            // Merge any locally-added sessions that haven't been saved to Apex yet
            this._restoreSessionsFromLocalStorage();
            if (Object.keys(mealsByDateAcc).length) {
                this.surveyMealsData = { ...this.surveyMealsData, mealsByDate: mealsByDateAcc };
            }
            this.buildFeeRowsFromSessions();
        } else {
            this.sessionsByDate = {};
        }
    }

    buildFeeRowsFromSessions() {
        const dateKeys = Object.keys(this.sessionsByDate || {});
        if (!dateKeys.length) {
            this.feeRowsByDate = [];
            this.feeSummaryTotal = 0;
            this.feedbackFormsByDate = [];
            return;
        }

        const sortedKeys = dateKeys.sort((a, b) => new Date(a) - new Date(b));
        const rows = sortedKeys.map(dateKey => {
            const sessions = (this.sessionsByDate[dateKey]?.sessions || []).map(session => ({
                ...session,
                price: session.sessionFee || '',
                isFree: !!session.noFee
            }));

            return {
                dateKey,
                displayDate: this.formatDateForDisplay(new Date(dateKey)),
                sessions
            };
        });

        this.feeRowsByDate = rows;
        this.calculateFeeTotals();
        this.buildFeedbackForms();
    }

    calculateFeeTotals() {
        let total = 0;
        this.feeRowsByDate.forEach(row => {
            row.sessions.forEach(session => {
                if (!session.isFree && session.price) {
                    total += parseFloat(session.price) || 0;
                }
            });
        });
        this.feeSummaryTotal = total;
    }

    // Step 5 (Fee Setup) - new Figma UI handlers
    handleFeeModeChange(event) {
        const { pricingMode } = event.detail || {};
        this.pricingMode = pricingMode || null;
    }

    handleFeeSessionPriceChange(event) {
        const { sessionId, dateKey, value } = event.detail || {};
        if (!sessionId || !dateKey) return;
        this.handleFeeInputChange({ target: { dataset: { sessionId, dateKey }, value } });
    }

    handleFeeSessionFreeToggle(event) {
        const { sessionId, dateKey, isFree } = event.detail || {};
        if (!sessionId || !dateKey) return;
        this.handleFeeFreeToggle({ target: { dataset: { sessionId, dateKey }, checked: isFree } });
    }

    handleFeeOverallPriceChange(event) {
        const { value } = event.detail || {};
        this.overallPrice = value;
        if (value !== '' && value !== null && value !== undefined) {
            this.overallIsFree = false;
        }
    }

    handleFeeOverallFreeToggle(event) {
        const { isFree } = event.detail || {};
        this.overallIsFree = !!isFree;
        if (this.overallIsFree) {
            this.overallPrice = '';
        }
    }

    handleMealFeesChanged(event) {
        const { value } = event.detail || {};
        this.mealFees = value;
    }

    handleFeeInputChange(event) {
        const { sessionId, dateKey } = event.target.dataset;
        const value = event.target.value;
        this.feeRowsByDate = this.feeRowsByDate.map(row => {
            if (row.dateKey !== dateKey) return row;
            const updatedSessions = row.sessions.map(session => {
                if (session.uniqueId === sessionId) {
                    return { ...session, price: value, isFree: false };
                }
                return session;
            });
            return { ...row, sessions: updatedSessions };
        });
        this.calculateFeeTotals();
    }

    handleFeeFreeToggle(event) {
        const { sessionId, dateKey } = event.target.dataset;
        const checked = event.target.checked;

        this.feeRowsByDate = this.feeRowsByDate.map(row => {
            if (row.dateKey !== dateKey) return row;
            const updatedSessions = row.sessions.map(session => {
                if (session.uniqueId === sessionId) {
                    return { ...session, isFree: checked, price: checked ? '' : session.price };
                }
                return session;
            });
            return { ...row, sessions: updatedSessions };
        });
        this.calculateFeeTotals();
    }

    openFeeSummaryModal() {
        const summarySessions = [];
        this.feeRowsByDate.forEach((row, rowIndex) => {
            row.sessions.forEach((session, sessionIndex) => {
                summarySessions.push({
                    id: `${row.dateKey}-${session.uniqueId || session.title}-${rowIndex}-${sessionIndex}`,
                    date: row.displayDate,
                    title: session.title,
                    time: session.timeRange || '',
                    price: session.isFree ? 'Free' : (session.price ? `₹${session.price}` : '—')
                });
            });
        });
        this.feeSummarySessions = summarySessions;
        this.showFeeSummaryModal = true;
    }

    closeFeeSummaryModal() {
        this.showFeeSummaryModal = false;
    }

    async handleSaveFeeStep() {
        try {
            if (!this.validateStep4()) {
                return;
            }
            this.showSpinner = true;
            // Allow proceeding even without eventId (development mode)
            // if (!this.currentEventId) {
            //     this.showToast('Error', 'Save event details before adding fees', 'error');
            //     return;
            // }
            // DEV MODE: allow proceeding even if pricing mode / values are not selected yet.
            // (Keep UI flow unblocked during development.)
            // Validation (production):
            // - if (!this.pricingMode) { ... }
            // - validate meal fees / session fees / overall fees ...

            let sessionPayload = [];
            let isEventWise = false;
            let eventFee = null;
            let isNoFee = false;

            // Build payload based on pricingMode (best-effort; skip save if nothing selected)
            if (this.pricingMode === 'SESSION_WISE') {
                for (const row of (this.feeRowsByDate || [])) {
                    for (const session of (row.sessions || [])) {
                        if (session.id) {
                            sessionPayload.push({
                                Id: session.id,
                                Session_Fee__c: session.isFree ? 0 : (parseFloat(session.price) || 0),
                                No_Fee__c: session.isFree
                            });
                        }
                    }
                }
                isEventWise = false;
            } else if (this.pricingMode === 'OVERALL') {
                isEventWise = true;
                isNoFee = !!this.overallIsFree;
                eventFee = isNoFee ? 0 : (parseFloat(this.overallPrice) || 0);
                sessionPayload = [];
            } else {
                // Nothing selected yet -> don't attempt fee save, just proceed
                sessionPayload = [];
                isEventWise = false;
                eventFee = null;
                isNoFee = false;
            }

            try {
                if (this.currentEventId) {
                    await updateFee({
                        isEventWise,
                        eventId: this.currentEventId,
                        eventFee,
                        isNoFee,
                        sessionsMap: sessionPayload
                    });
                }
            } catch (error) {
                console.error('Error saving fees, but proceeding anyway:', error);
            }

            try {
                if (this.currentEventId && this.surveyMealsData?.mealsPaidAddonEnabled &&
                    this.mealFees !== '' && this.mealFees != null) {
                    await saveMealFee({
                        eventId: this.currentEventId,
                        mealFee: parseFloat(this.mealFees) || 0
                    });
                }
            } catch (error) {
                console.error('Error saving meal fee, but proceeding anyway:', error);
            }

            this.isStep5Completed = true;
            this.currentStep = 6;
            this.showToast('Success', 'Proceeding to feedback form', 'success');
        } catch (error) {
            console.error('Error in handleSaveFeeStep, but proceeding anyway:', error);
            this.isStep5Completed = true;
            this.currentStep = 6;
        } finally {
            this.showSpinner = false;
        }
    }

    buildFeedbackForms() {
        const dateKeys = Object.keys(this.sessionsByDate || {});
        if (!dateKeys.length) {
            this.feedbackFormsByDate = [];
            return;
        }

        const sortedKeys = dateKeys.sort((a, b) => new Date(a) - new Date(b));
        this.feedbackFormsByDate = sortedKeys.map(dateKey => ({
            dateKey,
            displayDate: this.formatDateForDisplay(new Date(dateKey)),
            sessions: (this.sessionsByDate[dateKey]?.sessions || []).map(session => {
                const feedbackData = this.feedbackDataBySession[session.uniqueId];
                const hasForm = !!(feedbackData && Array.isArray(feedbackData.questions) && feedbackData.questions.length > 0);
                const questionsCount = feedbackData?.questions?.length || 0;
                return {
                    ...session,
                    hasForm,
                    questionsCount
                };
            })
        }));
    }

    handleSetupFeedbackForm(sessionIdOrEvent) {
        const sessionId = typeof sessionIdOrEvent === 'string'
            ? sessionIdOrEvent
            : sessionIdOrEvent?.detail?.sessionId || sessionIdOrEvent?.currentTarget?.dataset?.sessionId;
        if (!sessionId) {
            return;
        }
        this.feedbackFormsByDate = this.feedbackFormsByDate.map(row => ({
            ...row,
            sessions: row.sessions.map(session => session.uniqueId === sessionId
                ? { ...session, hasForm: true, questionsCount: 3 }
                : session)
        }));
    }

    handleEditFeedbackForm(sessionIdOrEvent) {
        const sessionId = typeof sessionIdOrEvent === 'string'
            ? sessionIdOrEvent
            : sessionIdOrEvent?.detail?.sessionId || sessionIdOrEvent?.currentTarget?.dataset?.sessionId;
        if (!sessionId) {
            return;
        }
        this.feedbackFormsByDate = this.feedbackFormsByDate.map(row => ({
            ...row,
            sessions: row.sessions.map(session => session.uniqueId === sessionId
                ? { ...session, hasForm: true, questionsCount: session.questionsCount || 3 }
                : session)
        }));
    }

    handleFeedbackAction(event) {
        const detail = event?.detail || {};
        const sessionId = detail.sessionId || event?.currentTarget?.dataset?.sessionId;
        if (!sessionId) {
            return;
        }
        this.activeFeedbackSessionId = sessionId;
    }

    get activeFeedbackSession() {
        if (!this.activeFeedbackSessionId || !this.feedbackFormsByDate || !this.feedbackFormsByDate.length) {
            return null;
        }
        let dayIndex = 0;
        for (const row of this.feedbackFormsByDate) {
            let sessionIndex = 0;
            for (const session of row.sessions || []) {
                if (session.uniqueId === this.activeFeedbackSessionId) {
                    const startStr = this.formatTimeForDisplay(session.startTime);
                    const endStr = this.formatTimeForDisplay(session.endTime);
                    const displayTime = (startStr && endStr) ? `${startStr} – ${endStr}` : (startStr || endStr || '');
                    return {
                        session,
                        dateKey: row.dateKey,
                        displayDate: row.displayDate,
                        dayIndex: dayIndex + 1,
                        sessionIndex: sessionIndex + 1,
                        totalSessionsInDay: (row.sessions || []).length,
                        displayTime
                    };
                }
                sessionIndex++;
            }
            dayIndex++;
        }
        return null;
    }

    get feedbackDataForSession() {
        if (!this.activeFeedbackSessionId) return null;
        const data = this.feedbackDataBySession[this.activeFeedbackSessionId];
        return data || {
            triggerType: 'auto',
            triggerWhen: '',
            endDate: '',
            endTime: '',
            questions: []
        };
    }

    handleFeedbackFormSave(event) {
        const { sessionId, triggerType, triggerWhen, endDate, endTime, questions } = event.detail || {};
        if (!sessionId) return;
        // Save to memory only — Apex save is deferred to handleProceedFromFeedback
        this.feedbackDataBySession = {
            ...this.feedbackDataBySession,
            [sessionId]: { triggerType, triggerWhen, endDate, endTime, questions: questions || [] }
        };
        this.buildFeedbackForms();
        this.activeFeedbackSessionId = null;
    }

    handleFeedbackFormDiscard() {
        this.activeFeedbackSessionId = null;
    }

    async persistFeedbackTriggerSettings(sessionId, triggerType, triggerWhen, endDate, endTime) {
        try {
            await saveFeedbackTriggerSettings({ sessionId, triggerType, triggerWhen, endDate, endTime });
        } catch (error) {
            console.error('Error saving feedback trigger settings:', error);
            this.showToast('Error', 'Failed to save feedback trigger settings', 'error');
        }
    }

    async persistFeedbackQuestionnaire(sessionId, questions) {
        try {
            const existing = this.feedbackDataBySession?.[sessionId] || {};
            const questionnaire = {
                Id: existing.questionnaireId || null
            };

            const questionsPayload = (questions || []).map(q => {
                const questionId = this.isSalesforceId(q.id) ? q.id : null;
                const typeValue = this.mapQuestionTypeForPicklist(q.type);
                const normalizedType = String(q.type || '').toLowerCase();
                const isLinear = normalizedType === 'linear' || normalizedType === 'linear scale';
                let MCQ_Options__c = '';
                if (isLinear) {
                    MCQ_Options__c = JSON.stringify({
                        scaleMin: q.scaleMin != null ? String(q.scaleMin) : '1',
                        scaleMax: q.scaleMax != null ? String(q.scaleMax) : '5',
                        scaleMinLabel: q.scaleMinLabel || '',
                        scaleMaxLabel: q.scaleMaxLabel || ''
                    });
                } else if (Array.isArray(q.options) && q.options.length) {
                    MCQ_Options__c = q.options.map(opt => opt.text).join(';');
                }
                return {
                    Id: questionId,
                    Question_Label__c: q.text || '',
                    Question_Type__c: typeValue,
                    Is_Required__c: q.required || false,
                    MCQ_Options__c
                };
            });

            const questionnaireId = await saveQuestionnaireForSession({
                sessionId,
                questionnaire,
                questions: questionsPayload
            });

            this.feedbackDataBySession = {
                ...this.feedbackDataBySession,
                [sessionId]: {
                    ...existing,
                    questionnaireId
                }
            };
        } catch (error) {
            console.error('Error saving feedback questionnaire:', error);
            this.showToast('Error', 'Failed to save feedback questions', 'error');
        }
    }

    formatDateToString(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    formatDateForDisplay(date) {
        return date.toLocaleDateString('en-US', {
            day: 'numeric',
            month: 'short',
            year: 'numeric'
        });
    }

    /**
     * Formats milliseconds-from-midnight (the shape an @AuraEnabled Apex Time
     * field arrives as) for display. Anything non-numeric is rejected rather
     * than rendered as "12:NaN AM" — pass "HH:mm" strings to
     * formatTimeForDisplay instead.
     */
    formatTimeDisplay(milliseconds) {
        if (milliseconds === null || milliseconds === undefined || milliseconds === '') return '';
        if (typeof milliseconds === 'string') return this.formatTimeForDisplay(milliseconds);
        if (typeof milliseconds !== 'number' || isNaN(milliseconds)) return '';

        const date = new Date(0);
        date.setMilliseconds(milliseconds);

        let hours = date.getUTCHours();
        const minutes = date.getUTCMinutes();
        if (isNaN(hours) || isNaN(minutes)) return '';

        const ampm = hours >= 12 ? 'PM' : 'AM';
        hours = hours % 12 || 12;

        const minutesStr = minutes.toString().padStart(2, '0');

        return `${hours}:${minutesStr} ${ampm}`;
    }

    formatTimeFromApex(milliseconds) {
        if (milliseconds === null || milliseconds === undefined) {
            return '';
        }

        // Convert milliseconds to total hours and minutes
        const date = new Date(milliseconds);

        let hours = date.getUTCHours();
        let minutes = date.getUTCMinutes();

        // Pad with leading zero if needed
        const formattedHours = hours.toString().padStart(2, '0');
        const formattedMinutes = minutes.toString().padStart(2, '0');

        return `${formattedHours}:${formattedMinutes}`;
    }

    normalizeTimeForApex(value) {
        if (!value) {
            return null;
        }

        const trimmed = value.trim();
        if (!trimmed) {
            return null;
        }

        // Already in 24h HH:mm format.
        if (/^\d{2}:\d{2}$/.test(trimmed)) {
            return trimmed;
        }

        // Convert 12h format like "10:36 PM" to 24h HH:mm.
        const match = trimmed.match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
        if (match) {
            let hours = parseInt(match[1], 10);
            const minutes = match[2];
            const meridiem = match[3].toUpperCase();

            if (meridiem === 'PM' && hours < 12) {
                hours += 12;
            } else if (meridiem === 'AM' && hours === 12) {
                hours = 0;
            }

            return `${hours.toString().padStart(2, '0')}:${minutes}`;
        }

        return null;
    }

    convertSpeakersFromApex(apexSpeakers) {
        return apexSpeakers.map((speaker, index) => {
            const image = speaker.speakerImage || null;
            const imageFileName = speaker.speakerImageFileName || this.getSpeakerImageFileName(image);
            return {
                id: speaker.Id || '',
                uniqueId: speaker.Id || Date.now().toString() + index,
                name: speaker.name || '',
                email: speaker.email || '',
                sendInvite: speaker.sendInvite === true,
                description: speaker.description || '',
                image,
                imageFileName
            };
        });
    }

    getSpeakerImageFileName(imageUrl) {
        if (!imageUrl) return '';
        // If already a filename (no slashes), return as-is.
        if (!imageUrl.includes('/')) return imageUrl;

        const withoutQuery = imageUrl.split('?')[0];
        const parts = withoutQuery.split('/');
        const lastPart = parts[parts.length - 1];
        return lastPart || 'Speaker image';
    }

    handleGlobalClick(event) {
        // Debug logging
        console.log('Global click detected on:', event.target.tagName, event.target.className);

        // Check if the click is inside any of the multi-select containers
        const isInsideCategoryDropdown = event.target.closest('.multi-select-container[data-field="category"]');
        const isInsideSuitableForDropdown = event.target.closest('.multi-select-container[data-field="suitableFor"]');
        const isInsideLanguageDropdown = event.target.closest('.multi-select-container[data-field="language"]');

        // Debug logging for dropdown detection
        console.log('Inside dropdowns:', {
            category: !!isInsideCategoryDropdown,
            suitableFor: !!isInsideSuitableForDropdown,
            language: !!isInsideLanguageDropdown
        });

        // Close dropdowns if click is outside their respective containers
        if (!isInsideCategoryDropdown) {
            this.showCategoryDropdown = false;
        }
        if (!isInsideSuitableForDropdown) {
            this.showSuitableForDropdown = false;
        }
        if (!isInsideLanguageDropdown) {
            this.showLanguageDropdown = false;
        }

        // Additional check: if clicking on form elements that's not part of the dropdowns, close all dropdowns
        if (event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA' || event.target.tagName === 'SELECT') {
            const isDropdownInput = event.target.closest('.multi-select-container');
            if (!isDropdownInput) {
                this.showCategoryDropdown = false;
                this.showSuitableForDropdown = false;
                this.showLanguageDropdown = false;
            }
        }

        // Additional check: if clicking on labels or other form elements, close all dropdowns
        if (event.target.tagName === 'LABEL' || event.target.closest('label')) {
            const isDropdownLabel = event.target.closest('.multi-select-container');
            if (!isDropdownLabel) {
                this.showCategoryDropdown = false;
                this.showSuitableForDropdown = false;
                this.showLanguageDropdown = false;
            }
        }

        // Additional check: if clicking on buttons or other interactive elements outside dropdowns
        if (event.target.tagName === 'BUTTON' || event.target.closest('button')) {
            const isDropdownButton = event.target.closest('.multi-select-container');
            if (!isDropdownButton) {
                this.showCategoryDropdown = false;
                this.showSuitableForDropdown = false;
                this.showLanguageDropdown = false;
            }
        }

        // Debug logging for final state
        console.log('Dropdown states after click:', {
            category: this.showCategoryDropdown,
            suitableFor: this.showSuitableForDropdown,
            language: this.showLanguageDropdown
        });
    }

    // Summary navigation (not used in 5-step flow)
    handleSummaryNavigate(event) {
        const detail = event?.detail || {};
        const stepIndex = Number(detail.stepIndex);
        if (!stepIndex || Number.isNaN(stepIndex)) {
            return;
        }
        // close any open modals when navigating
        this.showTriggeringFeedbackModal = false;
        this.showMissingFeedbackModal = false;
        this.currentStep = stepIndex;
    }

    // Helper method to close all dropdowns
    closeAllDropdowns() {
        this.showCategoryDropdown = false;
        this.showSuitableForDropdown = false;
        this.showLanguageDropdown = false;

        // Debug logging
        console.log('All dropdowns closed');

        // Force UI update
        this.template.querySelectorAll('.dropdown-options').forEach(dropdown => {
            if (dropdown.style.display !== 'none') {
                dropdown.style.display = 'none';
            }
        });
    }

    // Fallback method to close dropdowns - called when other methods fail
    forceCloseDropdowns() {
        // Force close all dropdowns
        this.showCategoryDropdown = false;
        this.showSuitableForDropdown = false;
        this.showLanguageDropdown = false;

        // Debug logging
        console.log('Dropdowns force closed');

        // Trigger a re-render to ensure UI updates
        this.template.querySelectorAll('.dropdown-options').forEach(dropdown => {
            dropdown.style.display = 'none';
        });
    }

    // Handle clicks on dropdown containers
    handleDropdownContainerClick(event) {
        // Debug logging
        console.log('Dropdown container clicked:', event.currentTarget.dataset.field);

        // Don't close dropdown if clicking inside the container
        // This method is mainly for debugging and ensuring proper event handling
        event.stopPropagation();
    }

    // Handle form blur events to close dropdowns
    handleFormBlur() {
        // Close all dropdowns when form loses focus
        this.closeAllDropdowns();

        // Debug logging
        console.log('Form blur detected, dropdowns closed');
    }

    // Handle form focus events
    handleFormFocus() {
        // Debug logging
        console.log('Form focus detected');
    }

    // Handle form submit events
    handleFormSubmit() {
        // Close all dropdowns when form is submitted
        this.closeAllDropdowns();

        // Debug logging
        console.log('Form submit detected, dropdowns closed');
    }

    // Handle form input events
    handleFormInput() {
        // Debug logging
        console.log('Form input detected');
    }

    // Handle form change events
    handleFormChange() {
        // Debug logging
        console.log('Form change detected');
    }

    // Handle form reset events
    handleFormReset() {
        // Close all dropdowns when form is reset
        this.closeAllDropdowns();

        // Debug logging
        console.log('Form reset detected, dropdowns closed');
    }

    // Handle form invalid events
    handleFormInvalid() {
        // Close all dropdowns when form validation fails
        this.closeAllDropdowns();

        // Debug logging
        console.log('Form invalid detected, dropdowns closed');
    }

    // Handle form valid events
    handleFormValid() {
        // Debug logging
        console.log('Form valid detected');
    }

    // Handle form reset events
    handleFormReset() {
        // Close all dropdowns when form is reset
        this.closeAllDropdowns();

        // Debug logging
        console.log('Form reset detected, dropdowns closed');
    }

    // Handle keyboard events (ESC key to close dropdowns)
    handleKeyDown(event) {
        if (event.key === 'Escape') {
            this.closeAllDropdowns();
        }
    }

    // Handle window resize events
    handleWindowResize() {
        // Close all dropdowns when window is resized to prevent positioning issues
        this.closeAllDropdowns();

        // Debug logging
        console.log('Window resized, dropdowns closed');
    }

    getPlainText(value) {
        if (value === undefined || value === null) {
            return '';
        }
        const str = String(value);
        if (str.indexOf('<') === -1) {
            return str;
        }
        const tmp = document.createElement('div');
        tmp.innerHTML = str;
        return tmp.textContent || tmp.innerText || '';
    }

    // Step 1: Event Setup Handlers - Child Component Event Handlers
    handleStep1DataChange(event) {
        if (!event || !event.detail) {
            return;
        }
        const { field, value, html } = event.detail;

        if (!field) {
            return;
        }

        switch (field) {
            case 'title':
                this.eventData.title = value;
                this.validateField('title', value);
                break;
            case 'maxParticipants':
                this.eventData.maxParticipants = value;
                this.validateField('maxParticipants', value);
                break;
            case 'description':
                this.eventData.description = html !== undefined ? html : value;
                this.validateField('description', this.eventData.description);
                break;
            case 'expectations':
                this.eventData.expectations = html !== undefined ? html : value;
                this.validateField('expectations', this.eventData.expectations);
                break;
            case 'agenda':
                this.eventData.agenda = html !== undefined ? html : value;
                this.validateField('agenda', this.eventData.agenda);
                break;
            case 'canBringGuests':
                this.eventData.canBringGuests = value;
                // Clear validation error when value is set
                if (value) {
                    this.validationErrors.canBringGuests = '';
                    // If changed to 'no', clear maxGuestsPerParticipant error
                    if (value === 'no') {
                        this.validationErrors.maxGuestsPerParticipant = '';
                    }
                }
                break;
            case 'maxGuestsPerParticipant':
                this.eventData.maxGuestsPerParticipant = value;
                // Clear validation error when value is set
                if (value && value > 0) {
                    this.validationErrors.maxGuestsPerParticipant = '';
                }
                break;
            default:
                break;
        }
    }

    handleStep1ValidationChange(event) {
        if (!event || !event.detail) {
            return;
        }
        const { field, error } = event.detail;
        if (this.validationErrors && field) {
            this.validationErrors[field] = error || '';
        }
    }

    handleAudienceChange(event) {
        const detail = event && event.detail ? event.detail : {};
        const audienceData = detail.selectedAudienceData || detail.selectedAudience || detail.audience || [];
        this.selectedAudienceData = Array.isArray(audienceData) ? audienceData : [];
    }

    // Group → "Create an Event" passes ONLY the group id in the URL (?preselectGroupId=…),
    // no sessionStorage — a later unrelated Host-Event entry (no param) can't inherit a
    // stale group. The wire is a backup source to the connectedCallback URL read.
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        if (!pageRef || this._groupPreselectConsumed) return;
        const state = pageRef.state || {};
        const groupId = state.preselectGroupId || state.c__preselectGroupId;
        if (!groupId) return;
        this._pendingPreselectGroup = { id: groupId };
        this.maybeApplyPreselectedGroup();
    }

    // Read the group id straight off the URL query string — robust to the LWR/Aura
    // difference in how CurrentPageReference.state prefixes custom params.
    readPreselectGroupIdFromUrl() {
        try {
            const params = new URLSearchParams(window.location.search || '');
            return params.get('preselectGroupId') || params.get('c__preselectGroupId') || null;
        } catch (e) {
            return null;
        }
    }

    // Seed the target audience from the launching group. Runs once, only for a fresh
    // event (not resume/edit), and only after connectedCallback's resetForm so it isn't
    // wiped. Resolves the group's name + live member count from the id (the URL only
    // carries the id). Called from both the page-ref wire and connectedCallback so it
    // works regardless of which settles first.
    maybeApplyPreselectedGroup() {
        if (this._groupPreselectConsumed) return;
        if (!this._hasConnected || !this._pendingPreselectGroup) return;
        if (this.currentEventId || this._recordId) { this._groupPreselectConsumed = true; return; }
        this._groupPreselectConsumed = true;
        const gid = this._pendingPreselectGroup.id;
        getAudienceGroupsByIds({ groupIds: [gid] })
            .then((rows) => {
                const g = (rows && rows[0]) || {};
                this.seedPreselectedGroup(gid, g.name, g.memberCount, g.membersLabel);
            })
            .catch(() => {
                // Name lookup failed — still seed by id so the preselection works.
                this.seedPreselectedGroup(gid, null, 0, '');
            });
    }

    seedPreselectedGroup(groupId, name, memberCount, membersLabel) {
        const groupItem = {
            id: groupId,
            role: 'GROUPS',
            roleLabel: 'Groups',
            title: name || 'Group',
            type: 'GROUP',
            memberCount: memberCount || 0,
            membersLabel: membersLabel || '',
            criteria: []
        };
        this.selectedAudienceData = [groupItem];
        this.preselectedAudience = [groupItem];
    }

    handleStep2DateChange(event) {
        if (!event || !event.detail) {
            return;
        }
        const { date } = event.detail;
        if (date) {
            // Handle date selection - this will be handled by handleDateClick
            // This method is called when datechange event is fired
            const [year, month, day] = date.split('-').map(Number);
            const clickDate = new Date(year, month - 1, day);

            const today = new Date();
            const todayLocal = new Date(today.getFullYear(), today.getMonth(), today.getDate());

            if (clickDate < todayLocal) return;

            const oneYearFromToday = new Date(today.getFullYear() + 1, today.getMonth(), today.getDate());
            if (clickDate > oneYearFromToday) {
                this.showToast('Error', 'Selected date cannot be more than one year from today', 'error');
                return;
            }

            const existingIndex = this.selectedDates.findIndex(d => d.value === date);

            if (existingIndex >= 0) {
                this.selectedDates.splice(existingIndex, 1);
            } else {
                this.selectedDates.push({
                    key: date,
                    value: date,
                    display: clickDate.toLocaleDateString('en-US', {
                        day: 'numeric',
                        month: 'short',
                        year: 'numeric'
                    })
                });
            }
            this.validateField('selectedDates', this.selectedDates);
            this.generateCalendar();
        }
    }

    handleStep2MonthChange(event) {
        if (!event || !event.detail) {
            return;
        }
        const { direction } = event.detail;
        if (direction === 'prev') {
            this.handlePrevMonth();
        } else if (direction === 'next') {
            this.handleNextMonth();
        }
    }

    // Step 3: Schedule Setup - Child Component Event Handlers
    handleStep3SessionChange(event) {
        if (!event || !event.detail) {
            return;
        }
        const { type, date, sessionId, value, file } = event.detail;
        
        if (type === 'dateTabChange') {
            this.activeDateTab = date;
            return;
        }
        
        if (type === 'toggleSession') {
            const dateKey = this.activeDateTab;
            const dateSessions = this.sessionsByDate[dateKey];
            if (!dateSessions || !Array.isArray(dateSessions.sessions)) {
                return;
            }

            // Preserve any in-progress work before switching which session is expanded:
            // 1) If the user is editing an already-saved session inline, merge those
            //    unsaved edits back into the list so re-expanding shows the latest values.
            // 2) If the user is part-way through adding a brand-new session (form open,
            //    not yet saved), stash it so it can be restored after they peek at
            //    another session instead of being silently cleared.
            const editedId = this.currentSession?.uniqueId;
            const isEditingExisting = editedId &&
                dateSessions.sessions.some(s => s.uniqueId === editedId);
            if (this.showSessionForm && !this.editingSessionId && this.hasSessionData(this.currentSession)) {
                this.pendingNewSession = {
                    ...this.currentSession,
                    speakers: [...(this.currentSession.speakers || [])]
                };
            }

            let updatedSession = null;
            const updatedSessions = dateSessions.sessions.map((session) => {
                let base = session;
                if (isEditingExisting && session.uniqueId === editedId) {
                    base = {
                        ...session,
                        ...this.currentSession,
                        speakers: [...(this.currentSession.speakers || session.speakers || [])]
                    };
                }

                if (base.uniqueId !== sessionId) {
                    return { ...base, isExpanded: false };
                }

                const currentlyExpanded = base.isExpanded !== undefined ? base.isExpanded : false;
                const isExpanded = !currentlyExpanded;
                updatedSession = { ...base, isExpanded };
                return updatedSession;
            });

            this.sessionsByDate = {
                ...this.sessionsByDate,
                [dateKey]: {
                    ...dateSessions,
                    sessions: updatedSessions
                }
            };

            if (updatedSession && updatedSession.isExpanded) {
                this.currentSession = {
                    ...updatedSession,
                    speakers: [...(updatedSession.speakers || [])]
                };
                this.showSessionForm = false;
                this.editingSessionId = null;
                this.editingSpeakerId = null;
            } else {
                // Collapsing the active session. Restore the stashed new-session form
                // (if any) so the user's input survives; otherwise reset to a clean state.
                this.editingSpeakerId = null;
                if (this.pendingNewSession) {
                    this.currentSession = {
                        ...this.pendingNewSession,
                        speakers: [...(this.pendingNewSession.speakers || [])]
                    };
                    this.pendingNewSession = null;
                    this.showSessionForm = true;
                    this.editingSessionId = null;
                } else if (this.currentSession?.uniqueId === sessionId) {
                    this.showSessionForm = false;
                    this.editingSessionId = null;
                    this.resetCurrentSession();
                }
            }
            this._saveSessionsToLocalStorage();
            return;
        }

        // Handle field changes
        if (this.currentSession && type) {
            const fieldMap = {
                'titleChange': 'title',
                'startTimeChange': 'startTime',
                'endTimeChange': 'endTime',
                'agendaChange': 'agenda',
                'locationTypeChange': 'locationType',
                'venueAddressChange': 'venueAddress',
                'eventLinkChange': 'eventLink'
            };
            
            const field = fieldMap[type];
            if (field && value !== undefined) {
                this.currentSession[field] = value;
                this.currentSession = { ...this.currentSession };
            }

            const errorMap = {
                'titleChange': 'sessionTitle',
                'startTimeChange': 'sessionStartTime',
                'endTimeChange': 'sessionEndTime',
                'agendaChange': 'sessionAgenda',
                'locationTypeChange': 'locationType'
            };
            const errKey = errorMap[type];
            if (errKey && value) {
                this.validationErrors = { ...this.validationErrors, [errKey]: '' };
            }

            if (type === 'startTimeChange' || type === 'endTimeChange') {
                this.validateTimeRange();
            }

            if (type === 'eventLinkChange' || type === 'venueAddressChange') {
                this.validateLocationFields();
                this.validationErrors = { ...this.validationErrors };
            }
            
            if (type === 'brochureUpload' && file) {
                this.handleSessionBrochureUpload({ target: { files: [file] } });
            }
            
            if (type === 'removeBrochure') {
                this.currentSession.brochure = null;
                this.currentSession.brochureFileName = '';
                this.currentSession = { ...this.currentSession };
            }
        }
        
        // Legacy support for old format
        const { field: oldField, value: oldValue } = event.detail;
        if (this.currentSession && oldField && oldValue !== undefined) {
            this.currentSession[oldField] = oldValue;
            this.currentSession = { ...this.currentSession };
        }
    }

    handleStep3SessionFormToggle(event) {
        if (!event || !event.detail) {
            return;
        }
        const { show } = event.detail;
        this.showSessionForm = show !== undefined ? show : !this.showSessionForm;
    }

    // Step 4: Fee Setup - Child Component Event Handlers
    handleStep4FeeChange(event) {
        if (!event || !event.detail) {
            return;
        }
        const { feeRowsByDate, feeSummaryTotal } = event.detail;
        if (feeRowsByDate) {
            this.feeRowsByDate = feeRowsByDate;
        }
        if (feeSummaryTotal !== undefined) {
            this.feeSummaryTotal = feeSummaryTotal;
        }
    }

    // Step 5: Survey Setup - Child Component Event Handlers
    handleStep5SurveyChange(event) {
        if (!event || !event.detail) {
            return;
        }
        // Handle new survey structure
        const { 
            offerMealsEnabled, 
            mealsByDate, 
            mealsPaidAddonEnabled,
            dietaryEnabled,
            dietaryOptions,
            customSurveyEnabled,
            surveyQuestions,
            surveyMandatory 
        } = event.detail;
        
        // Update survey questions if provided
        if (surveyQuestions) {
            this.surveyQuestions = surveyQuestions;
        }
        if (surveyMandatory !== undefined) {
            this.surveyMandatory = surveyMandatory;
        }
        
        // Store new meal and dietary data (for persistence). Merge so a partial emit can never drop
        // the per-date meal selections that the Summary step reads.
        if (offerMealsEnabled !== undefined) {
            this.surveyMealsData = {
                ...this.surveyMealsData,
                offerMealsEnabled,
                mealsByDate: mealsByDate !== undefined ? mealsByDate : this.surveyMealsData?.mealsByDate,
                mealsPaidAddonEnabled,
                dietaryEnabled,
                dietaryOptions
            };
        }
        if (customSurveyEnabled !== undefined) {
            this.customSurveyEnabled = customSurveyEnabled;
        }
    }

    handleQuestionRequiredChange(event) {
        if (!event || !event.detail) {
            return;
        }
        const { questionId, value } = event.detail;
        this.surveyQuestions = this.surveyQuestions.map(q => 
            q.id === questionId ? { ...q, required: value } : q
        );
    }

    // Step 5: Feedback Form - Child Component Event Handlers
    handleStep6FeedbackChange(event) {
        if (!event || !event.detail) {
            return;
        }
        const { feedbackFormsByDate } = event.detail;
        if (feedbackFormsByDate) {
            this.feedbackFormsByDate = feedbackFormsByDate;
        }
    }

    // Step 1: Event Setup Handlers
    handleCoverPhotoUploadScreen() {
        // This event is handled by the child component directly
        // No action needed in parent as child component handles the file input click
    }

    handleCoverPhotoUpload(event) {
        if (!event || !event.detail) {
            return;
        }
        
        const file = event.detail.file;
        if (file) {
            if (file.size > 2 * 1024 * 1024) {
                this.validationErrors.coverPhoto = 'Cover photo must be 2 MB or smaller';
                this.showToast('Error', this.validationErrors.coverPhoto, 'error');
                return;
            }

            if (!file.type.match('image/(png|jpeg|jpg)')) {
                this.validationErrors.coverPhoto = 'Please select a PNG or JPEG image';
                this.showToast('Error', this.validationErrors.coverPhoto, 'error');
                return;
            }

            const reader = new FileReader();
            reader.onload = (e) => {
                const dataUrl = e.target.result;
                const img = new Image();
                img.onload = () => {
                    if (img.width < img.height * 1.5) {
                        this.validationErrors.coverPhoto =
                            'Cover photo must be in landscape format. Try using a wider image.';
                        this.showToast('Error', this.validationErrors.coverPhoto, 'error');
                        return;
                    }
                    this.eventData.coverImage = dataUrl;
                    this.eventData.coverImageFileName = file.name;
                    this.validationErrors.coverPhoto = '';
                };
                img.onerror = () => {
                    this.validationErrors.coverPhoto = 'Could not read image dimensions';
                    this.showToast('Error', this.validationErrors.coverPhoto, 'error');
                };
                img.src = dataUrl;
            };

            reader.onerror = () => {
                this.validationErrors.coverPhoto = 'Failed to read image file';
                this.showToast('Error', this.validationErrors.coverPhoto, 'error');
            };
            reader.readAsDataURL(file);
        }
    }


    handleDeleteCoverImage() {
        console.log('Removing cover photo');
        this.eventData.coverImage = '';
        this.eventData.coverImageFileName = '';
        // Show validation error when cover photo is deleted
        this.validationErrors.coverPhoto = 'Cover photo is required';
    }

    handleEventTitleChange(event) {
        this.eventData.title = event.target.value;
        this.validateField('title', this.eventData.title);
    }

    handleCategoryChange(event) {
        this.eventData.category = event.target.value;
    }

    handleMaxParticipantsChange(event) {
        const rawValue = event.target.value;

        if (rawValue === '' || rawValue === null) {
            this.eventData.maxParticipants = '';
            this.validateField('maxParticipants', this.eventData.maxParticipants);
            return;
        }

        const numericValue = Number(rawValue);

        if (Number.isNaN(numericValue)) {
            this.eventData.maxParticipants = '';
            event.target.value = '';
            this.validationErrors.maxParticipants = 'Please enter a valid number';
            return;
        }

        if (numericValue < 0) {
            this.eventData.maxParticipants = '';
            event.target.value = '';
            this.validationErrors.maxParticipants = 'Value cannot be negative';
            return;
        }

        const sanitizedValue = Math.floor(numericValue).toString();
        event.target.value = sanitizedValue;
        this.eventData.maxParticipants = sanitizedValue;
        this.validateField('maxParticipants', this.eventData.maxParticipants);
    }

    handleDescriptionChange(event) {
        const value = event.target.value;

        if (value.length > 1000) {
            const trimmedValue = value.slice(0, 1000);
            event.target.value = trimmedValue;
            this.eventData.description = trimmedValue;
            this.validationErrors.description = 'Maximum 1000 characters allowed';
            return;
        }

        this.eventData.description = value;
        this.validateField('description', this.eventData.description);
    }

    // handleExpectationsChange(event) {
    //     this.eventData.expectations = event.target.value;
    //     this.validationErrors.expectations = '';
    // }

    handleSuitableForChange(event) {
        this.eventData.suitableFor = event.target.value;
    }

    handleLanguageChange(event) {
        this.eventData.language = event.target.value;
    }

    handleBrochureUpload(event) {
        const file = event?.detail?.file || event?.target?.files?.[0];
        const inputEl = event?.target;

        if (!file) {
            this.validationErrors.brochure = '';
            this.eventData.broucherFileName = '';
            this.eventData.brochure = null;
            return;
        }

        if (file.type !== 'application/pdf') {
            this.validationErrors.brochure = 'Only PDF files are allowed';
            if (inputEl && Object.prototype.hasOwnProperty.call(inputEl, 'value')) {
                inputEl.value = '';
            }
            this.eventData.brochure = null;
            this.eventData.broucherFileName = '';
            return;
        }

        if (file.size > 2 * 1024 * 1024) {
            this.validationErrors.brochure = 'File size must not exceed 2 MB';
            if (inputEl && Object.prototype.hasOwnProperty.call(inputEl, 'value')) {
                inputEl.value = '';
            }
            this.eventData.brochure = null;
            this.eventData.broucherFileName = '';
            return;
        }

        this.validationErrors.brochure = '';

        const reader = new FileReader();
        reader.onload = (e) => {
            this.eventData.brochure = e.target.result;
            this.eventData.broucherFileName = file.name;
        };
        reader.onerror = (error) => {
            this.showToast('Error', 'Failed to read file', 'error');
        };
        reader.readAsDataURL(file);
    }

    handleBrochureChangeUpload(event) {
        const file = event?.detail?.file || event?.target?.files?.[0];
        const inputEl = event?.target;

        if (!file) return;

        if (file.type !== 'application/pdf') {
            this.validationErrors.brochure = 'Only PDF files are allowed';
            if (inputEl && Object.prototype.hasOwnProperty.call(inputEl, 'value')) {
                inputEl.value = '';
            }
            this.eventData.brochure = null;
            this.eventData.broucherFileName = '';
            return;
        }

        if (file.size > 2 * 1024 * 1024) {
            this.validationErrors.brochure = 'File size must not exceed 2 MB';
            this.eventData.brochure = null;
            this.eventData.broucherFileName = '';
            if (inputEl && Object.prototype.hasOwnProperty.call(inputEl, 'value')) {
                inputEl.value = '';
            }
            return;
        }

        this.validationErrors.brochure = '';

        const reader = new FileReader();
        reader.onload = (e) => {
            this.eventData.brochure = e.target.result;
            this.eventData.broucherFileName = file.name;
        };
        reader.onerror = (error) => {
            this.showToast('Error', 'Failed to read file', 'error');
        };
        reader.readAsDataURL(file);
    }

    handleChangeBrochure() {
        const tempInput = document.createElement('input');
        tempInput.type = 'file';
        tempInput.accept = '.pdf,application/pdf';
        tempInput.style.display = 'none';

        tempInput.onchange = (event) => {
            this.handleBrochureChangeUpload(event);
            document.body.removeChild(tempInput);
        };

        document.body.appendChild(tempInput);
        tempInput.click();
    }

    handleRemoveBrochure() {
        this.eventData.brochure = null;
        this.eventData.broucherFileName = '';
    }

    // Multi-select dropdown handlers
    handleCategoryDropdownToggle(event) {
        event.preventDefault();
        event.stopPropagation();
        this.showCategoryDropdown = !this.showCategoryDropdown;
        this.showSuitableForDropdown = false;
        this.showLanguageDropdown = false;

        // Debug logging
        console.log('Category dropdown toggled:', this.showCategoryDropdown);
    }

    handleSuitableForDropdownToggle(event) {
        event.preventDefault();
        event.stopPropagation();
        this.showSuitableForDropdown = !this.showSuitableForDropdown;
        this.showCategoryDropdown = false;
        this.showLanguageDropdown = false;

        // Debug logging
        console.log('SuitableFor dropdown toggled:', this.showSuitableForDropdown);
    }

    handleLanguageDropdownToggle(event) {
        event.preventDefault();
        event.stopPropagation();
        this.showLanguageDropdown = !this.showLanguageDropdown;
        this.showCategoryDropdown = false;
        this.showSuitableForDropdown = false;

        // Debug logging
        console.log('Language dropdown toggled:', this.showLanguageDropdown);
    }

    handleCategorySelect(event) {
        if (!event || !event.detail) {
            return;
        }
        
        event.stopPropagation();

        const value = event.detail.value;
        if (!value) {
            return;
        }

        const option = this.eventCategories.find(opt => opt.value === value);

        if (option) {
            option.selected = !option.selected;

            const existingIndex = this.selectedCategories.findIndex(cat =>
                (typeof cat === 'object' ? cat.value : cat) === value
            );

            if (existingIndex >= 0) {
                this.selectedCategories.splice(existingIndex, 1);
            } else {
                this.selectedCategories.push({
                    key: value,
                    value: value,
                    label: option.label
                });
            }

            this.eventData.categories = this.selectedCategories.map(cat =>
                typeof cat === 'object' ? cat.value : cat
            );

            this.eventCategories = [...this.eventCategories];

            // Clear validation error if categories are selected
            if (this.selectedCategories.length > 0) {
                this.validationErrors.category = '';
            }
        }
    }

    handleLanguageSelect(event) {
        if (!event || !event.detail) {
            return;
        }
        
        event.stopPropagation();

        const value = event.detail.value;
        if (!value) {
            return;
        }

        const option = this.eventLanguages.find(opt => opt.value === value);

        if (option) {
            option.selected = !option.selected;

            const existingIndex = this.selectedLanguages.findIndex(lang =>
                (typeof lang === 'object' ? lang.value : lang) === value
            );

            if (existingIndex >= 0) {
                this.selectedLanguages.splice(existingIndex, 1);
            } else {
                this.selectedLanguages.push({
                    key: value,
                    value: value,
                    label: option.label
                });
            }

            this.eventData.languages = this.selectedLanguages.map(lang =>
                typeof lang === 'object' ? lang.value : lang
            );

            this.eventLanguages = [...this.eventLanguages];

            // Clear validation error if languages are selected
            if (this.selectedLanguages.length > 0) {
                this.validationErrors.language = '';
            }
        }
    }

    handleSuitableForSelect(event) {
        if (!event || !event.detail) {
            return;
        }
        
        event.stopPropagation();

        const value = event.detail.value;
        if (!value) {
            return;
        }

        const option = this.suitableForData.find(opt => opt.value === value);

        if (option) {
            option.selected = !option.selected;

            const existingIndex = this.selectedSuitableFor.findIndex(item =>
                (typeof item === 'object' ? item.value : item) === value
            );

            if (existingIndex >= 0) {
                this.selectedSuitableFor.splice(existingIndex, 1);
            } else {
                this.selectedSuitableFor.push({
                    key: value,
                    value: value,
                    label: option.label
                });
            }

            this.eventData.targetAudienceApplicable = this.selectedSuitableFor.map(item =>
                typeof item === 'object' ? item.value : item
            );

            this.suitableForData = [...this.suitableForData];

            // Clear validation error if suitable for options are selected
            if (this.selectedSuitableFor.length > 0) {
                this.validationErrors.suitableFor = '';
            }
        }
    }


    handleRemoveCategory(event) {
        if (!event || !event.detail) {
            return;
        }
        
        event.stopPropagation();

        const value = event.detail.value;
        if (!value) {
            return;
        }

        const index = this.selectedCategories.findIndex(cat =>
            (typeof cat === 'object' ? cat.value : cat) === value
        );

        if (index >= 0) {
            this.selectedCategories.splice(index, 1);
            this.eventData.categories = this.selectedCategories.map(cat =>
                typeof cat === 'object' ? cat.value : cat
            );

            const option = this.eventCategories.find(opt => opt.value === value);
            if (option) {
                option.selected = false;
            }

            this.eventCategories = [...this.eventCategories];

            // Show validation error if no categories are selected
            if (this.selectedCategories.length === 0) {
                this.validationErrors.category = 'Please select at least one category';
            }
        }
    }

    handleRemoveLanguage(event) {
        if (!event || !event.detail) {
            return;
        }
        
        event.stopPropagation();

        const value = event.detail.value;
        if (!value) {
            return;
        }

        const index = this.selectedLanguages.findIndex(lang =>
            (typeof lang === 'object' ? lang.value : lang) === value
        );

        if (index >= 0) {
            this.selectedLanguages.splice(index, 1);
            this.eventData.languages = this.selectedLanguages.map(lang =>
                typeof lang === 'object' ? lang.value : lang
            );

            const option = this.eventLanguages.find(opt => opt.value === value);
            if (option) {
                option.selected = false;
            }

            this.eventLanguages = [...this.eventLanguages];

            // Show validation error if no languages are selected
            if (this.selectedLanguages.length === 0) {
                this.validationErrors.language = 'Please select at least one language';
            }
        }
    }

    handleRemoveSuitableFor(event) {
        if (!event || !event.detail) {
            return;
        }
        
        event.stopPropagation();

        const value = event.detail.value;
        if (!value) {
            return;
        }

        const index = this.selectedSuitableFor.findIndex(item =>
            (typeof item === 'object' ? item.value : item) === value
        );

        if (index >= 0) {
            this.selectedSuitableFor.splice(index, 1);
            this.eventData.targetAudienceApplicable = this.selectedSuitableFor.map(item =>
                typeof item === 'object' ? item.value : item
            );

            const option = this.suitableForData.find(opt => opt.value === value);
            if (option) {
                option.selected = false;
            }

            this.suitableForData = [...this.suitableForData];

            // Show validation error if no suitable for options are selected
            if (this.selectedSuitableFor.length === 0) {
                this.validationErrors.suitableFor = 'Please select target audience';
            }
        }
    }

    handleClearLanguages() {
        this.selectedLanguages = [];
        this.eventData.languages = [];
        // Show validation error when languages are cleared
        this.validationErrors.language = 'Please select at least one language';
    }

    // Validation functions
    validateField(fieldName, value) {
        switch (fieldName) {
            case 'title':
                if (!value || !value.trim()) {
                    this.validationErrors.title = 'This field is required';
                } else if (value.trim().length >= 50) {
                    this.validationErrors.title = 'Title must not exceed 50 characters';
                } else {
                    this.validationErrors.title = '';
                }
                break;
            case 'maxParticipants':
                if (value === undefined || value === null || value === '') {
                    this.validationErrors.maxParticipants = 'This field is required';
                } else {
                    const numericValue = Number(value);
                    if (Number.isNaN(numericValue)) {
                        this.validationErrors.maxParticipants = 'Please enter a valid number';
                    } else if (numericValue < 0) {
                        this.validationErrors.maxParticipants = 'Value cannot be negative';
                    } else {
                        this.validationErrors.maxParticipants = '';
                    }
                }
                break;
            case 'description': {
                const plain = this.getPlainText(value).trim();
                if (!plain) {
                    this.validationErrors.description = 'This field is required';
                } else if (plain.length < 10) {
                    this.validationErrors.description = 'Description must be at least 10 characters';
                } else if (plain.length > 1000) {
                    this.validationErrors.description = 'Maximum 1000 characters allowed';
                } else {
                    this.validationErrors.description = '';
                }
                break;
            }
            case 'expectations': {
                const plain = this.getPlainText(value).trim();
                if (!plain) {
                    this.validationErrors.expectations = 'This field is required';
                } else if (plain.length < 10) {
                    this.validationErrors.expectations = 'This field must be at least 10 characters';
                } else if (plain.length > 1000) {
                    this.validationErrors.expectations = 'Maximum 1000 characters allowed';
                } else {
                    this.validationErrors.expectations = '';
                }
                break;
            }
            case 'agenda': {
                const plain = this.getPlainText(value).trim();
                if (plain.length > 1000) {
                    this.validationErrors.agenda = 'Maximum 1000 characters allowed';
                } else {
                    this.validationErrors.agenda = '';
                }
                break;
            }
            case 'sessionTitle':
                if (!value || !value.trim()) {
                    this.validationErrors.sessionTitle = 'This field is required';
                } else if (value.trim().length >= 100) {
                    this.validationErrors.sessionTitle = 'Title must not exceed 100 characters';
                } else {
                    this.validationErrors.sessionTitle = '';
                }
                break;
            case 'sessionAgenda': {
                const trimmedAgenda = value ? value.trim() : '';
                if (!trimmedAgenda) {
                    this.validationErrors.sessionAgenda = 'This field is required';
                } else if (trimmedAgenda.length > 255) {
                    this.validationErrors.sessionAgenda = 'Agenda must not exceed 255 characters';
                } else {
                    this.validationErrors.sessionAgenda = '';
                }
                break;
            }
            case 'speakerName': {
                const trimmedValue = value ? value.trim() : '';
                if (!trimmedValue) {
                    this.validationErrors.speakerName = 'Speaker name is required';
                } else if (trimmedValue.length >= 50) {
                    this.validationErrors.speakerName = 'Speaker name must not exceed 50 characters';
                } else if (/\d/.test(trimmedValue)) {
                    this.validationErrors.speakerName = 'Speaker name cannot contain numbers';
                } else if (!/^[a-zA-Z\s.'-]+$/.test(trimmedValue)) {
                    this.validationErrors.speakerName = 'Speaker name can only contain letters, spaces, periods, hyphens, and apostrophes';
                } else {
                    this.validationErrors.speakerName = '';
                }
                break;
            }
            case 'speakerEmail': {
                const email = (value || '').trim();
                const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
                if (email && !emailRe.test(email)) {
                    this.validationErrors.speakerEmail = 'Please enter a valid email address';
                } else {
                    this.validationErrors.speakerEmail = '';
                }
                break;
            }
            case 'coverPhoto':
                this.validationErrors.coverPhoto = value ? '' : 'Cover photo is required';
                break;
            case 'selectedDates':
                if (this.selectedDates.length === 0) {
                    this.validationErrors.selectedDates = 'At least one date must be selected';
                } else {
                    const today = new Date();
                    today.setHours(0, 0, 0, 0);
                    const oneYearFromToday = new Date(today.getFullYear() + 1, today.getMonth(), today.getDate());

                    const invalidDates = this.selectedDates.filter(dateObj => {
                        const selectedDate = new Date(dateObj.value);
                        selectedDate.setHours(0, 0, 0, 0);
                        return selectedDate > oneYearFromToday;
                    });

                    if (invalidDates.length > 0) {
                        this.validationErrors.selectedDates = 'Selected dates cannot be more than one year from today';
                    } else {
                        this.validationErrors.selectedDates = '';
                    }
                }
                break;
            case 'brochure':
                if (!value) {
                    this.validationErrors.brochure = '';
                } else if (value.type !== 'application/pdf') {
                    this.validationErrors.brochure = 'Only PDF files are allowed';
                } else if (value.size > 2 * 1024 * 1024) {
                    this.validationErrors.brochure = 'File size must not exceed 2 MB';
                } else {
                    this.validationErrors.brochure = '';
                }
                break;
        }
    }

    validateStep1() {
        // Validate required fields
        this.validateField('title', this.eventData.title);
        this.validateField('expectations', this.eventData.expectations);
        this.validateField('coverPhoto', this.eventData.coverImage);

        // Validate multi-select fields
        if (this.selectedCategories.length === 0) {
            this.validationErrors.category = 'Please select at least one category';
        } else {
            this.validationErrors.category = '';
        }

        // Validate date selection (moved to step 1)
        if (this.selectedDates.length === 0) {
            this.validationErrors.selectedDates = 'Please select at least one date';
        } else {
            this.validationErrors.selectedDates = '';
        }

        // Validate guest fields
        if (!this.eventData.canBringGuests) {
            this.validationErrors.canBringGuests = 'Please select whether guests are allowed';
        } else {
            this.validationErrors.canBringGuests = '';
            
            // Validate maxGuestsPerParticipant only if canBringGuests is 'yes'
            if (this.eventData.canBringGuests === 'yes') {
                if (!this.eventData.maxGuestsPerParticipant || this.eventData.maxGuestsPerParticipant <= 0) {
                    this.validationErrors.maxGuestsPerParticipant = 'Please specify how many guests each participant can bring';
                } else {
                    this.validationErrors.maxGuestsPerParticipant = '';
                }
            } else {
                this.validationErrors.maxGuestsPerParticipant = '';
            }
        }

        // Optional fields - clear errors if they exist
        this.validationErrors.maxParticipants = '';
        this.validationErrors.description = '';
        this.validationErrors.agenda = '';
        this.validationErrors.suitableFor = '';
        this.validationErrors.language = '';
    }

    hasValidationErrors(fields = []) {
        const errors = this.validationErrors || {};
        return (fields || []).some(field => {
            const value = errors[field];
            if (value === null || value === undefined) {
                return false;
            }
            if (typeof value === 'string') {
                return value.trim().length > 0;
            }
            return !!value;
        });
    }

    validateStep2() {
        if (!this.hasTargetAudienceSelection) {
            this.validationErrors.suitableFor = 'Please select target audience';
            this.validationErrors = { ...this.validationErrors };
            return false;
        }
        if (this.validationErrors.suitableFor) {
            this.validationErrors.suitableFor = '';
            this.validationErrors = { ...this.validationErrors };
        }
        return true;
    }

    validateStep3() {
        if (!Array.isArray(this.selectedDates) || this.selectedDates.length === 0) {
            this.showToast('Error', 'Please select at least one date before adding sessions', 'error');
            return false;
        }

        const allDatesHaveSessions = this.selectedDates.every(date => {
            const sessions = this.sessionsByDate[date.key];
            return sessions && sessions.sessions && sessions.sessions.length > 0;
        });

        if (!allDatesHaveSessions) {
            this.showToast('Error', 'Please add at least one session for each selected date', 'error');
            return false;
        }

        if (this.shouldShowSessionForm) {
            this.validateSession();
            this.validationErrors = { ...this.validationErrors };

            const sessionErrorFields = [
                'sessionTitle',
                'sessionStartTime',
                'sessionEndTime',
                'timeRange',
                'sessionAgenda',
                'locationType',
                'eventLink',
                'venueAddress',
                'sessionBrochure'
            ];

            if (this.hasValidationErrors(sessionErrorFields)) {
                this.showToast('Error', 'Please fill all required fields and fix validation errors', 'error');
                return false;
            }
        }

        return true;
    }

    validateStep4() {
        if (!this.pricingMode) {
            this.showToast('Error', 'Please select a pricing mode', 'error');
            return false;
        }

        if (this.pricingMode === 'OVERALL') {
            if (!this.overallIsFree) {
                const price = Number(this.overallPrice);
                if (this.overallPrice === '' || this.overallPrice === null || Number.isNaN(price) || price < 0) {
                    this.showToast('Error', 'Please enter an overall price or mark the event as free', 'error');
                    return false;
                }
            }
        } else if (this.pricingMode === 'SESSION_WISE') {
            const hasInvalidSession = (this.feeRowsByDate || []).some(row =>
                (row.sessions || []).some(session => {
                    if (session.isFree) {
                        return false;
                    }
                    const price = Number(session.price);
                    return session.price === '' || session.price === null || Number.isNaN(price) || price < 0;
                })
            );
            if (hasInvalidSession) {
                this.showToast('Error', 'Please enter a price for each paid session or mark it as free', 'error');
                return false;
            }
        }

        if (this.surveyMealsData?.mealsPaidAddonEnabled) {
            const mealFee = Number(this.mealFees);
            if (this.mealFees === '' || this.mealFees === null || Number.isNaN(mealFee) || mealFee < 0) {
                this.showToast('Error', 'Please enter a valid meal fee amount', 'error');
                return false;
            }
        }

        return true;
    }

    handleAgendaChange(event) {
        const value = event.target.value;

        if (value.length > 1000) {
            const trimmedValue = value.slice(0, 1000);
            event.target.value = trimmedValue;
            this.eventData.agenda = trimmedValue;
            this.validationErrors.agenda = 'Maximum 1000 characters allowed';
            return;
        }

        this.eventData.agenda = value;
        this.validateField('agenda', this.eventData.agenda);
    }

    handleCancel() {
        this.closeAllDropdowns();
        this.showCancelConfirmModal = true;
    }

    get cancelConfirmMessage() {
        return this.currentEventId
            ? 'If you cancel, your progress will be saved as a draft. You can continue editing it later. Do you want to cancel?'
            : 'Are you sure you want to cancel? Any unsaved changes will be lost.';
    }

    handleCancelConfirmNo() {
        this.showCancelConfirmModal = false;
    }

    async handleCancelConfirmYes() {
        this.showCancelConfirmModal = false;
        if (this.currentEventId) {
            try {
                this.showSpinner = true;
                await this.saveEventData(this.currentStep, { suppressToast: true });
            } catch (e) {
                console.error('Error saving draft on cancel:', e);
            } finally {
                this.showSpinner = false;
            }
        }
        sessionStorage.removeItem('currentEventId');
        this.resetForm();
        this.navigateToHome();
    }

     navigateToHome() {
        const isPortal = !!this.cBasePath;
        if (isPortal) {
            // Experience/portal context: the internal object list view doesn't exist here and would
            // land on an error page, so route to the community Hosted Events page (/hosted-events).
            this.navigateToHostedEvents();
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Ken_Event_Master__c',
                actionName: 'list'
            },
            state: {
                filterName: 'Active_EVents'
            }
        }, true);
    }
    //
    handleOptionalCheckbox(event) {
        this.sendEmail = event.target.checked;
        console.log('Send Email checkbox:', this.sendEmail);
    }
    handleEmailDistributionChange(event) {
        this.emailDistributionList = Array.from(event.target.selectedOptions).map(opt => opt.value);
    }
    handleEmailSubjectChange(event) {
        this.emailSubject = event.target.value;
    }
    handleUploadButtonClick() {
        this.template.querySelector('input[type="file"]').click();
    }

    handleFileChange(event) {
        const file = event.target.files[0];
        if (file) {
            this.selectedFileName = file.name;
            // Validate size/type here if needed
            if (file.size > 1024 * 1024) {
                alert('File is too large (Max 1MB)');
                return;
            }
            if (!['image/png', 'image/jpeg'].includes(file.type)) {
                alert('Invalid file type. Only PNG and JPEG are allowed.');
                return;
            }
            const reader = new FileReader();
            reader.onload = () => {
                // Get the base64 part only
                const base64 = reader.result.split(',')[1];
                uploadFileToRecord({
                    recordId: this.currentEventId,   // make sure this is set from parent
                    fileName: file.name,
                    base64Data: base64,
                    contentType: file.type
                })
                    .then(result => {
                        // result will be the ContentDocumentId of the uploaded file
                        alert('File uploaded successfully!');
                        // Optionally, refresh the file list, show link, etc.
                    })
                    .catch(error => {
                        alert('Upload failed: ' + JSON.stringify(error));
                    });
            };
            console.log('recordId:', this.currentEventId);
            reader.readAsDataURL(file);
        }
    }


    async handleSaveAndProceed() {
        // Always close dropdowns when proceeding to next step
        this.closeAllDropdowns();

        this.showSpinner = true;

        try {
            // Email validation
            // if (this.sendEmail) {
            //     if (!this.emailSubject || !this.emailSubject.trim()) {
            //         this.showToast('Error', 'Email subject is required when Send Email is checked.', 'error');
            //         this.showSpinner = false;
            //         return;
            //     }
            //     // Add more email field validations here if needed
            // }
            if (this.currentStep === 1) {
                this.validateStep1();
                this.validationErrors = { ...this.validationErrors };
                const step1ErrorFields = [
                    'title',
                    'expectations',
                    'coverPhoto',
                    'category',
                    'selectedDates',
                    'canBringGuests',
                    'maxGuestsPerParticipant',
                    'maxParticipants',
                    'description',
                    'agenda',
                    'brochure'
                ];
                if (this.isStep1Invalid || this.hasValidationErrors(step1ErrorFields)) {
                    this.showToast('Error', 'Please fill all required fields and fix validation errors', 'error');
                    return;
                }

                try {
                await this.saveEventData(1);
                } catch (error) {
                    console.error('Error saving step 1, but proceeding anyway:', error);
                }

                this.isStep1Completed = true;
                this.validationErrors = {};
                this.currentStep = 2;
                this.generateCalendar();
            } else if (this.currentStep === 2) {
                if (!this.validateStep2()) {
                    this.showToast('Error', 'Please select target audience before proceeding', 'error');
                    return;
                }

                // The target audience must be SAVED (persisted) and LINKED to the event
                // before advancing. This gate runs BEFORE saveEventData(2): the event save
                // reassigns currentEventId, which can remount the audience builder and wipe
                // its dirty flag mid-flight — the gate must see the builder's real state.
                // audienceLinked defaults to false and is computed outside any swallowing
                // catch, so a missing component, a thrown error, or an unsaved segmentation
                // all BLOCK the step instead of slipping to step 3 without a real audience.
                let audienceLinked = false;
                const targetAudienceCmp = this.template.querySelector('c-ken-target-audience');
                if (targetAudienceCmp) {
                    try {
                        if (typeof targetAudienceCmp.persistCurrentSelection === 'function') {
                            await targetAudienceCmp.persistCurrentSelection();
                        }
                        if (typeof targetAudienceCmp.ensureEventSegmentationLink === 'function') {
                            audienceLinked = await targetAudienceCmp.ensureEventSegmentationLink();
                        }
                    } catch (error) {
                        console.warn('Segmentation persist/link failed:', error);
                        audienceLinked = false;
                    }
                }
                if (!audienceLinked && !(targetAudienceCmp && targetAudienceCmp.hasUnsavedChanges)) {
                    audienceLinked = await this.isAudienceLinkedOnServer(targetAudienceCmp);
                }
                if (!audienceLinked) {
                    // Not saved yet — tell the user, then open the save dialog so they can
                    // name + save the current audience. They can't advance until it's saved.
                    this.showToast('Error', 'Please save your target audience to continue.', 'error');
                    if (targetAudienceCmp && typeof targetAudienceCmp.openSaveDialog === 'function') {
                        targetAudienceCmp.openSaveDialog();
                    }
                    return;
                }

                try {
                await this.saveEventData(2);
                } catch (error) {
                    console.error('Error saving step 2, but proceeding anyway:', error);
                }

                this.validationErrors.selectedDates = '';
                this.isStep2Completed = true;
                this.currentStep = 3;
                if (this.selectedDates.length > 0) {
                this.activeDateTab = this.selectedDates[0].key;
                }
            }
        } catch (error) {
            console.error('Error in handleSaveAndProceed, but proceeding anyway:', error);
        } finally {
            this.showSpinner = false;
        }
    }

    /**
     * Server-truth fallback for the step-2 audience gate, consulted only when the
     * selection has NO unsaved edits (a dirty selection must save or block). The
     * wrapper/builder can report false from stale client state (or throw) even after
     * a successful save, so before blocking we accept the step when the event already
     * has a linked segmentation — or the audience is saved and the event record does
     * not exist yet.
     */
    async isAudienceLinkedOnServer(targetAudienceCmp) {
        const savedSegId = targetAudienceCmp ? targetAudienceCmp.segmentationId : null;
        const parentId = this.currentEventId;
        if (!parentId) {
            return !!savedSegId;
        }
        try {
            const linked = await getLinkedSegmentation({ parentObjectType: 'Event', parentId });
            return !!linked;
        } catch (e) {
            console.warn('Linked-audience fallback check failed', e);
            return false;
        }
    }

    async saveEventData(step, options = {}) {
        try {

            let eventStartDate = null;
            let eventEndDate = null;
            if (this.selectedDates && this.selectedDates.length > 0) {
                const sortedDates = this.selectedDates
                    .map(dateObj => (dateObj.value))
                    .sort((a, b) => a - b);

                eventStartDate = sortedDates[0];
                eventEndDate = sortedDates[sortedDates.length - 1];
            }

            const toDateOrNull = v => (v === '' || v == null) ? null : v;
            const eventWrapper = {
                Id: this.currentEventId,
                eventTitle: this.eventData.title,
                eventTypes: this.selectedCategories.map(cat => cat.value).join(';'),
                description: this.eventData.description,
                agenda: this.eventData.agenda,
                eventExpectations: this.eventData.expectations,
                maximumNumberOfParticipants: parseInt(this.eventData.maxParticipants) || null,
                eventLanguages: this.selectedLanguages.map(lang => lang.value).join(';'),
                targetAudienceApplicable: this.selectedSuitableFor.map(item => item.value).join(';'),
                image: this.eventData.coverImage,
                imageFileName: this.eventData.coverImageFileName || 'EventBanner.jpg',
                broucherFileName: this.eventData.broucherFileName || 'EventBrochure.pdf',
                broucher: this.eventData.brochure,
                currentstep: step,
                isPortal: true,
                startDate: toDateOrNull(eventStartDate),
                endDate: toDateOrNull(eventEndDate),
                eventStatus: options.submit ? 'In Review' : 'Draft',
                noFee: true,
                enrollTargetAudience: true,
                canAlumniBringGuests: this.eventData.canBringGuests === 'yes',
                guestCount: this.eventData.canBringGuests === 'yes'
                    ? (parseInt(this.eventData.maxGuestsPerParticipant, 10) || 0)
                    : 0,
                emailSubject: this.shareEmailSubject,
                emailDistributionList: this.selectedEmailDistributionList.map(item => item.value).join(';'),
                ScheduleDate: this.scheduleDate,
                ScheduleTime: this.shareEmailTime,
                emailBody: this.shareEmailBody,
                emailAttachments: this.emailAttachments
            };

            const constituentRoleId = localStorage.getItem('ConstituentRoleId');
            this.currentEventId = await saveEvent({
                eventData: JSON.stringify(eventWrapper),
                constituentRoleId
            });

            if (step == 2) {
                try {
                    await deleteSessionsData({
                        selectedDates: this.selectedDates.map(dateObj => dateObj.value),
                        eventId: this.currentEventId
                    });



                    await refreshApex(this.wiredEventScheduleResponse);
                } catch (error) {
                    console.log('Error deleting deselected session data:', error);
                }
            }

            if (!options.suppressToast && step != 3 && !options.submit) {
                if (this.currentEventId) {
                    sessionStorage.setItem('currentEventId', this.currentEventId);
                }

                const message = this.isEditMode ? 'updated' : 'saved';
                this.showToast('Save Success!', `Step ${step} ${message} successfully`, 'success');
            }
        } catch (error) {
            console.log('error', error);
            throw error;
        }
    }

    // Step 2: Date Selection Handlers
    handlePrevMonth() {
        this.currentDate = new Date(this.currentDate.getFullYear(), this.currentDate.getMonth() - 1, 1);
        this.generateCalendar();
    }

    handleNextMonth() {
        this.currentDate = new Date(this.currentDate.getFullYear(), this.currentDate.getMonth() + 1, 1);
        this.generateCalendar();
    }

    handleDateClick(event) {
        const dateStr = event.currentTarget.dataset.date;

        const [year, month, day] = dateStr.split('-').map(Number);
        const clickDate = new Date(year, month - 1, day);

        const today = new Date();
        const todayLocal = new Date(today.getFullYear(), today.getMonth(), today.getDate());

        if (clickDate < todayLocal) return;

        const oneYearFromToday = new Date(today.getFullYear() + 1, today.getMonth(), today.getDate());
        if (clickDate > oneYearFromToday) {
            this.showToast('Error', 'Selected date cannot be more than one year from today', 'error');
            return;
        }

        const existingIndex = this.selectedDates.findIndex(d => d.value === dateStr);

        if (existingIndex >= 0) {
            this.selectedDates.splice(existingIndex, 1);
        } else {
            this.selectedDates.push({
                key: dateStr,
                value: dateStr,
                display: clickDate.toLocaleDateString('en-US', {
                    day: 'numeric',
                    month: 'short',
                    year: 'numeric'
                })
            });
        }
        this.validateField('selectedDates', this.selectedDates);
        this.generateCalendar();
    }

    handleRemoveDate(event) {
        if (!event || !event.detail) return;
        const dateStr = event.detail.date;
        const index = this.selectedDates.findIndex(d => d.value === dateStr);
        if (index >= 0) {
            this.selectedDates.splice(index, 1);
            this.generateCalendar();
        }
    }

    handlePreviousStep() {
        if (this.currentStep > 1) {
            // Always close dropdowns when navigating between steps
            this.closeAllDropdowns();

            //this.saveCurrentStepData();
            let target = this.currentStep - 1;
            // Fee Setup (step 5) is skipped when fees are disabled for the org.
            if (this.feeDisabled && target === 5) {
                target = 4;
            }
            this.currentStep = target;
        }
    }

    async saveCurrentStepData() {
        try {
            if (this.currentEventId) {
                await this.saveEventData(this.currentStep);
            }
        } catch (error) {
            console.error('Error saving current step data:', error);
        }
    }

    // Step 3: Schedule Setup Handlers
    handleDateTabClick(event) {
        this.activeDateTab = event.currentTarget.dataset.date;

        // Reset editing states when switching tabs
        this.editingSessionId = null;
        this.editingSpeakerId = null;
        this.showSessionForm = false;
        this.showSpeakerForm = false;

        this.resetCurrentSession();

        // Show session form for empty dates
        // if (this.selectedDates.length > 0 && this.currentDateSessions.sessions.length === 0) {
        //     this.showSessionForm = true;
        //     this.resetCurrentSession();
        // }
    }

    handleAddSession() {
        const dateKey = this.activeDateTab || (this.selectedDates?.[0]?.key || '');
        if (!dateKey) {
            this.showToast('Error', 'Please select a date before adding a session', 'error');
            return;
        }
        this.activeDateTab = dateKey;

        const dateSessions = this.sessionsByDate[dateKey] || { sessions: [] };

        // If a card is currently expanded for editing, validate & commit it first so the
        // user can't add a second session while the current one is incomplete.
        const editingId = this.currentSession?.uniqueId;
        const isEditingExisting = editingId && dateSessions.sessions.some(s => s.uniqueId === editingId);
        if (isEditingExisting) {
            if (!this._validateCurrentSessionFields()) {
                this.showToast('Error', 'Please complete the current session before adding another', 'error');
                return;
            }
            this._commitCurrentCard();
        }

        // Add a fresh, expanded blank session card (all other cards collapse)
        const refreshed = this.sessionsByDate[dateKey] || { sessions: [] };
        const uniqueId = this.generateUniqueId();
        const blank = {
            id: '', uniqueId, key: uniqueId,
            title: '', startTime: '', endTime: '', agenda: '',
            brochure: null, brochureFileName: '', brochureFileType: '',
            locationType: 'online', venueAddress: '', eventLink: '',
            noFee: true, speakers: [], isExpanded: true, timeRange: ''
        };
        const sessions = refreshed.sessions.map(s => ({ ...s, isExpanded: false })).concat(blank);
        this.sessionsByDate = {
            ...this.sessionsByDate,
            [dateKey]: { ...refreshed, sessions }
        };

        this.currentSession = { ...blank };
        this.pendingNewSession = null;
        this.showSessionForm = false;
        this.editingSessionId = null;
        this.editingSpeakerId = null;
        this.validationErrors = {};
        this._saveSessionsToLocalStorage();
    }

    _timeRange(session) {
        if (session.startTime && session.endTime) {
            return `${this.formatTimeForDisplay(session.startTime)} - ${this.formatTimeForDisplay(session.endTime)}`;
        }
        return session.startTime ? this.formatTimeForDisplay(session.startTime) : '';
    }

    // Validate the currently-edited session (currentSession) and populate inline errors.
    _validateCurrentSessionFields() {
        this.validationErrors = {
            ...this.validationErrors,
            sessionTitle: '', sessionStartTime: '', sessionEndTime: '',
            timeRange: '', sessionAgenda: '', locationType: '', eventLink: '', venueAddress: ''
        };
        let ok = true;

        if (!this.currentSession.title?.trim()) {
            this.validationErrors.sessionTitle = 'Session title is required';
            ok = false;
        }
        if (!this.currentSession.startTime) {
            this.validationErrors.sessionStartTime = 'Start time is required';
            ok = false;
        }
        if (!this.currentSession.endTime) {
            this.validationErrors.sessionEndTime = 'End time is required';
            ok = false;
        }
        const agenda = (this.currentSession.agenda || '').trim();
        if (!agenda) {
            this.validationErrors.sessionAgenda = 'Session agenda is required';
            ok = false;
        } else if (agenda.length > 255) {
            this.validationErrors.sessionAgenda = 'Session agenda must not exceed 255 characters';
            ok = false;
        }
        if (!this.currentSession.locationType) {
            this.validationErrors.locationType = 'Location type is required';
            ok = false;
        }
        if (this.currentSession.startTime && this.currentSession.endTime) {
            if (this.timeToMinutes(this.currentSession.endTime) <= this.timeToMinutes(this.currentSession.startTime)) {
                this.validationErrors.timeRange = 'End time must be later than start time';
                ok = false;
            }
        }
        this.validateLocationFields();
        if (this.validationErrors.eventLink || this.validationErrors.venueAddress) ok = false;

        this.validationErrors = { ...this.validationErrors };
        return ok;
    }

    // Merge the in-progress currentSession edits back into its card (collapses it).
    _commitCurrentCard() {
        const dateKey = this.activeDateTab;
        const dateSessions = this.sessionsByDate[dateKey];
        if (!dateSessions) return;
        const id = this.currentSession?.uniqueId;
        if (!id) return;
        if (!dateSessions.sessions.some(s => s.uniqueId === id)) return;

        const sessions = dateSessions.sessions.map(s => {
            if (s.uniqueId !== id) return s;
            return {
                ...s,
                ...this.currentSession,
                uniqueId: s.uniqueId,
                id: s.id,
                key: s.key,
                isExpanded: false,
                timeRange: this._timeRange(this.currentSession)
            };
        });
        this.sessionsByDate = {
            ...this.sessionsByDate,
            [dateKey]: { ...dateSessions, sessions }
        };
        this._saveSessionsToLocalStorage();
    }

    // True when a session's location-specific fields are incomplete/invalid.
    _locationInvalid(session) {
        const isValidUrl = (url) => !!url && (url.startsWith('https://') || url.startsWith('www.') || url.includes('.com'));
        if (session.locationType === 'online') return !isValidUrl(session.eventLink);
        if (session.locationType === 'onsite') return !session.venueAddress;
        if (session.locationType === 'hybrid') return !isValidUrl(session.eventLink) || !session.venueAddress;
        return false;
    }

    // Walk every session across all dates; if any is invalid, expand it, show inline
    // errors and return false. Returns true when all sessions are complete.
    _validateAllSessionsAndFocus() {
        for (const dateKey of Object.keys(this.sessionsByDate)) {
            const sessions = this.sessionsByDate[dateKey].sessions || [];
            for (const s of sessions) {
                const invalid = !s.title?.trim() || !s.startTime || !s.endTime ||
                    !(s.agenda || '').trim() || !s.locationType ||
                    (s.startTime && s.endTime && this.timeToMinutes(s.endTime) <= this.timeToMinutes(s.startTime)) ||
                    this._locationInvalid(s);
                if (invalid) {
                    this.activeDateTab = dateKey;
                    this.currentSession = { ...s, speakers: [...(s.speakers || [])] };
                    this.sessionsByDate = {
                        ...this.sessionsByDate,
                        [dateKey]: {
                            ...this.sessionsByDate[dateKey],
                            sessions: sessions.map(x => ({ ...x, isExpanded: x.uniqueId === s.uniqueId }))
                        }
                    };
                    this._validateCurrentSessionFields();
                    return false;
                }
            }
        }
        return true;
    }

    // True when a session object carries any user-entered content worth preserving.
    hasSessionData(session) {
        if (!session) {
            return false;
        }
        return !!(session.title || session.agenda || session.startTime || session.endTime ||
            session.venueAddress || session.eventLink || session.brochure ||
            (session.speakers && session.speakers.length));
    }

    hasSessionValidationErrors() {
        return !this.currentSession.title ||
            !this.currentSession.startTime ||
            !this.currentSession.endTime ||
            !this.currentSession.locationType ||
            !this.currentSession.agenda ||
            this.timeRangeError;
    }

    validateSession() {
        this.validateField('sessionTitle', this.currentSession.title);
        this.validateField('sessionAgenda', this.currentSession.agenda);

        if (!this.currentSession.startTime) {
            this.validationErrors.sessionStartTime = 'Start time is required';
        } else {
            this.validationErrors.sessionStartTime = '';
        }

        if (!this.currentSession.endTime) {
            this.validationErrors.sessionEndTime = 'End time is required';
        } else {
            this.validationErrors.sessionEndTime = '';
        }

        if (!this.currentSession.locationType) {
            this.validationErrors.locationType = 'Location type is required';
        } else {
            this.validationErrors.locationType = '';
        }

        this.validateTimeRange();
        this.validateLocationFields();
    }

    handleEditSession(event) {
        const sessionId = event.currentTarget.dataset.sessionId;
        const session = this.currentDateSessions.sessions.find(s => s.uniqueId === sessionId);
        if (session) {
            this.editingSessionId = sessionId;
            this.currentSession = {
                ...session,
                speakers: [...(session.speakers || [])]
            };

            this.sessionsByDate = { ...this.sessionsByDate };

            this.showSessionForm = false;
            this.editingSpeakerId = null;
        }
    }

    async handleDeleteSession(event) {
        const sessionUniqueId = event?.detail?.sessionId || event?.currentTarget?.dataset?.sessionId;
        if (!sessionUniqueId) {
            return;
        }

        const dateKey = this.activeDateTab;
        const dateSessions = this.sessionsByDate[dateKey];
        const existingSessions = dateSessions?.sessions || [];
        const sessionToDelete = existingSessions.find(s => s.uniqueId === sessionUniqueId);

        try {
            this.showSpinner = true;

            const sessionId = sessionToDelete?.id;
            if (sessionId) {
                await deleteEventSession({ recordId: sessionId });
            }

            this.validationErrors = {
                sessionTitle: '',
                sessionStartTime: '',
                sessionEndTime: '',
                timeRange: '',
                sessionAgenda: '',
                locationType: '',
                eventLink: '',
                venueAddress: ''
            };

            this.sessionsByDate = {
                ...this.sessionsByDate,
                [dateKey]: {
                    ...dateSessions,
                    sessions: existingSessions.filter(session => session.uniqueId !== sessionUniqueId)
                }
            };

            // Clear the working copy if the deleted card was the one being edited
            if (this.editingSessionId === sessionUniqueId || this.currentSession?.uniqueId === sessionUniqueId) {
                this.resetCurrentSession();
                this.showSessionForm = false;
                this.editingSessionId = null;
            }

            // Keep the draft store in sync (removes locally-added sessions too)
            this._saveSessionsToLocalStorage();

            if (sessionId) {
                await refreshApex(this.wiredEventScheduleResponse);
            }

            this.showToast('Success', 'Session deleted successfully', 'success');
        } catch (error) {
            console.error('Delete session failed:', error);
            this.showToast('Error', 'Failed to delete session', 'error');
        } finally {
            this.showSpinner = false;
        }
    }

    handleSessionTitleChange(event) {
        this.currentSession.title = event.target.value;
        this.validateField('sessionTitle', this.currentSession.title);
    }

    handleStartTimeChange(event) {
        const newStartTime = event.target.value;
        this.currentSession.startTime = newStartTime;

        if (newStartTime) {
            this.validationErrors.sessionStartTime = '';
        }

        this.validateTimeRange();
        this.currentSession = { ...this.currentSession };
        this.validationErrors = { ...this.validationErrors };
    }

    handleEndTimeChange(event) {
        const newEndTime = event.target.value;
        this.currentSession.endTime = newEndTime;

        if (newEndTime) {
            this.validationErrors.sessionEndTime = '';
        }

        this.validateTimeRange();
        this.currentSession = { ...this.currentSession };
        this.validationErrors = { ...this.validationErrors };
    }

    validateTimeRange() {
        if (!this.validationErrors) {
            this.validationErrors = {};
        }

        this.validationErrors.timeRange = '';

        const hasStartTime = this.currentSession.startTime && this.currentSession.startTime.trim() !== '';
        const hasEndTime = this.currentSession.endTime && this.currentSession.endTime.trim() !== '';

        if (hasStartTime && hasEndTime) {
            const startTime = this.timeToMinutes(this.currentSession.startTime);
            const endTime = this.timeToMinutes(this.currentSession.endTime);

            if (endTime <= startTime) {
                this.validationErrors.timeRange = 'End time must be later than start time';
            }
        }

        this.validationErrors = { ...this.validationErrors };
    }

    timeToMinutes(timeString) {
        if (!timeString) return 0;
        const [hours, minutes] = timeString.split(':').map(Number);
        return hours * 60 + minutes;
    }

    updateTimeRange() {
        if (this.currentSession.startTime && this.currentSession.endTime) {
            const startTimeFormatted = this.formatTimeForDisplay(this.currentSession.startTime);
            const endTimeFormatted = this.formatTimeForDisplay(this.currentSession.endTime);
            this.currentSession.timeRange = `${startTimeFormatted} - ${endTimeFormatted}`;
        } else {
            this.currentSession.timeRange = '';
        }
    }

    /**
     * Formats an "HH:mm" string for display. Also accepts the raw
     * milliseconds-from-midnight a Salesforce Time field arrives as, so a
     * caller holding either shape renders correctly instead of "12:NaN AM".
     */
    formatTimeForDisplay(timeString) {
        if (timeString === null || timeString === undefined || timeString === '') return '';
        if (typeof timeString === 'number') return this.formatTimeDisplay(timeString);

        const parts = String(timeString).split(':');
        const hour = parseInt(parts[0], 10);
        const minutes = parseInt(parts[1], 10);
        if (isNaN(hour) || isNaN(minutes)) return '';

        const ampm = hour >= 12 ? 'PM' : 'AM';
        const displayHour = hour % 12 || 12;
        return `${displayHour}:${String(minutes).padStart(2, '0')} ${ampm}`;
    }

    handleSessionAgendaChange(event) {
        this.currentSession.agenda = event.target.value;
        this.validateField('sessionAgenda', this.currentSession.agenda);
    }

    handleSessionBrochureUpload(event) {
        const file = event?.target?.files?.[0];

        this.validationErrors = {
            ...this.validationErrors,
            sessionBrochure: ''
        };

        if (!file) {
            this.currentSession.brochure = null;
            this.currentSession.brochureFileName = '';
            this.currentSession.brochureFileType = '';
            this.currentSession = { ...this.currentSession };
            return;
        }

        const allowedMimeTypes = new Set([
            'application/pdf',
            'image/png',
            'image/jpeg',
            'application/msword',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        ]);
        const fileExtension = file.name?.split('.').pop()?.toLowerCase();
        const allowedExtensions = new Set(['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx']);
        const isMimeAllowed = file.type && allowedMimeTypes.has(file.type);
        const isExtAllowed = fileExtension && allowedExtensions.has(fileExtension);

        if (!isMimeAllowed && !isExtAllowed) {
            this.validationErrors = {
                ...this.validationErrors,
                sessionBrochure: 'Invalid file type. Allowed: PDF, PNG, JPG, DOC, DOCX'
            };
            event.target.value = '';
            this.currentSession.brochure = null;
            this.currentSession.brochureFileName = '';
            this.currentSession.brochureFileType = '';
            this.currentSession = { ...this.currentSession };
            this.showToast('Error', this.validationErrors.sessionBrochure, 'error');
            return;
        }

        if (file.size > 5 * 1024 * 1024) {
            this.validationErrors = {
                ...this.validationErrors,
                sessionBrochure: 'File size must not exceed 5 MB'
            };
            this.currentSession.brochure = null;
            this.currentSession.brochureFileName = '';
            this.currentSession.brochureFileType = '';
            event.target.value = '';
            this.currentSession = { ...this.currentSession };
            this.showToast('Error', this.validationErrors.sessionBrochure, 'error');
            return;
        }

        const reader = new FileReader();
        reader.onload = (e) => {
            this.currentSession.brochure = e.target.result;
            this.currentSession.brochureFileName = file.name;
            this.currentSession.brochureFileType = file.type || '';
            this.currentSession = { ...this.currentSession };
            this.showToast('Success', `Brochure "${file.name}" selected successfully`, 'success');
            console.log('✅ Session brochure uploaded:', file.name);
        };
        reader.onerror = (error) => {
            this.showToast('Error', 'Failed to read session brochure file', 'error');
            console.error('❌ Error reading brochure file:', error);
            this.currentSession.brochure = null;
            this.currentSession.brochureFileName = '';
            this.currentSession.brochureFileType = '';
            this.currentSession = { ...this.currentSession };
        };
        reader.readAsDataURL(file);
    }

    handleChangeSessionBrochure() {
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = '.png,.jpeg,.jpg,.pdf,.doc,.docx';
        input.onchange = (event) => {
            this.handleSessionBrochureUpload(event);
        };
        document.body.appendChild(input);
        input.click();
        document.body.removeChild(input);
    }

    handleRemoveSessionBrochure() {
        this.currentSession.brochure = null;
        this.currentSession.brochureFileName = '';
    }

    handleSpeakerNameChange(event) {
        let value = event.target.value;

        value = value.replace(/[0-9]/g, '');

        if (value !== event.target.value) {
            event.target.value = value;
        }

        this.currentSpeaker.name = value;
        this.validateField('speakerName', this.currentSpeaker.name);
    }


    handleSpeakerEmailChange(event) {
        this.currentSpeaker.email = event.target.value;
        this.validateField('speakerEmail', this.currentSpeaker.email);
    }

    handleSpeakerInviteToggle(event) {
        this.currentSpeaker.sendInvite = event.target.checked;
    }

    handleSpeakerImageUpload(event) {
        const file = event.target.files[0];
        if (file) {
            if (file.size > 1024 * 1024) {
                this.showToast('Error', 'Image must be <1 MB', 'error');
                return;
            }

            if (!file.type.match('image/(png|jpeg|jpg)')) {
                this.showToast('Error', 'Please select a PNG or JPEG image', 'error');
                return;
            }

            const reader = new FileReader();
            reader.onload = (e) => {
                this.currentSpeaker.image = e.target.result;
                this.currentSpeaker.imageFileName = file.name;
            };
            reader.readAsDataURL(file);
        }
    }

    handleSpeakerImageChangeUpload(event) {
        this.handleSpeakerImageUpload(event);
    }

    handleChangeSpeakerImage() {
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = '.png,.jpeg,.jpg';
        input.onchange = (event) => {
            this.handleSpeakerImageUpload(event);
        };
        document.body.appendChild(input);
        input.click();
        document.body.removeChild(input);
    }

    handleRemoveSpeakerImage() {
        this.currentSpeaker.image = null;
        this.currentSpeaker.imageFileName = '';
    }

    handleSpeakerDescriptionChange(event) {
        this.currentSpeaker.description = event.target.value;
        // Clear validation error when user types
        if (this.currentSpeaker.description.trim()) {
            this.validationErrors.speakerDescription = '';
        }
    }

    handleLocationTypeChange(event) {
        this.currentSession.locationType = event.target.value;
        // Clear location type validation error when a selection is made
        if (this.currentSession.locationType) {
            this.validationErrors.locationType = '';
        }
        // Validate location-specific fields based on selection
        this.validateLocationFields();
    }



    validateLocationFields() {
        // Clear previous errors
        this.validationErrors.eventLink = '';
        this.validationErrors.venueAddress = '';

        const isValidUrl = (url) =>
            url.startsWith('https://') || url.startsWith('www.') || url.includes('.com');

        if (this.currentSession.locationType === 'online') {
            if (!this.currentSession.eventLink) {
                this.validationErrors.eventLink = 'This field is required for Online event';
            } else if (!isValidUrl(this.currentSession.eventLink)) {
                this.validationErrors.eventLink = 'Please enter a valid URL';
            }
        } else if (this.currentSession.locationType === 'onsite') {
            if (!this.currentSession.venueAddress) {
                this.validationErrors.venueAddress = 'This field is required for On University Campus event';
            }
        } else if (this.currentSession.locationType === 'hybrid') {
            if (!this.currentSession.eventLink) {
                this.validationErrors.eventLink = 'This field is required for Hybrid event';
            } else if (!isValidUrl(this.currentSession.eventLink)) {
                this.validationErrors.eventLink = 'Please enter a valid URL';
            }
            if (!this.currentSession.venueAddress) {
                this.validationErrors.venueAddress = 'This field is required for Hybrid event';
            }
        }
    }

    handleVenueAddressChange(event) {
        this.currentSession.venueAddress = event.target.value;
        this.validateLocationFields();
    }

    handleEventLinkChange(event) {
        this.currentSession.eventLink = event.target.value;
        this.validateLocationFields();
    }

    handleSaveSpeaker() {
        this.validationErrors.speakerName = '';
        this.validationErrors.speakerEmail = '';

        let hasErrors = false;

        this.validateField('speakerName', this.currentSpeaker.name);
        this.validateField('speakerEmail', this.currentSpeaker.email);

        // An email is mandatory when an invite is requested for this speaker.
        if (this.currentSpeaker.sendInvite && !(this.currentSpeaker.email || '').trim()) {
            this.validationErrors.speakerEmail = 'Email is required to send an invite';
        }

        if (this.validationErrors.speakerName || this.validationErrors.speakerEmail) {
            hasErrors = true;
        }

        if (hasErrors) {
            this.showToast('Error', 'Please fix the validation errors before saving', 'error');
            return;
        }

        const speakerId = this.editingSpeakerId || this.generateUniqueId();
        const speaker = {
            ...this.currentSpeaker,
            uniqueId: speakerId,
        };

        if (this.editingSpeakerId) {
            const index = this.currentSession.speakers.findIndex(s => s.uniqueId === this.editingSpeakerId);
            if (index !== -1) {
                this.currentSession.speakers[index] = speaker;
            }
            this.editingSpeakerId = null;
        } else {
            if (!this.currentSession.speakers) {
                this.currentSession.speakers = [];
            }
            this.currentSession.speakers.push(speaker);
        }

        this.resetCurrentSpeaker();
        this.showSpeakerForm = false;

        this.showToast('Success', 'Speaker details saved successfully', 'success');
    }

    // --- localStorage helpers for draft sessions (no Apex ID yet) ---

    _saveSessionsToLocalStorage() {
        try {
            const eventId = this.currentEventId;
            if (!eventId) return;
            const localSessions = {};
            Object.entries(this.sessionsByDate).forEach(([date, { sessions }]) => {
                const local = (sessions || []).filter(s => !s.id);
                if (local.length) localSessions[date] = local;
            });
            localStorage.setItem(`ken_draft_sessions_${eventId}`, JSON.stringify(localSessions));
        } catch (e) { /* storage unavailable */ }
    }

    _restoreSessionsFromLocalStorage() {
        try {
            const eventId = this.currentEventId;
            if (!eventId) return;
            const stored = localStorage.getItem(`ken_draft_sessions_${eventId}`);
            if (!stored) return;
            const localSessions = JSON.parse(stored);
            if (!localSessions || typeof localSessions !== 'object') return;

            const merged = { ...this.sessionsByDate };
            Object.entries(localSessions).forEach(([date, sessions]) => {
                if (!merged[date]) merged[date] = { sessions: [] };
                sessions.forEach(local => {
                    const exists = merged[date].sessions.some(s => s.uniqueId === local.uniqueId);
                    if (!exists) merged[date].sessions.push(local);
                });
            });
            this.sessionsByDate = merged;
        } catch (e) { /* storage unavailable */ }
    }

    _clearSessionsFromLocalStorage() {
        try {
            const eventId = this.currentEventId;
            if (!eventId) return;
            localStorage.removeItem(`ken_draft_sessions_${eventId}`);
        } catch (e) { /* storage unavailable */ }
    }

    async handleSaveSession() {
        this.validationErrors.sessionTitle = '';
        this.validationErrors.sessionStartTime = '';
        this.validationErrors.sessionEndTime = '';
        this.validationErrors.timeRange = '';
        this.validationErrors.locationType = '';
        this.validationErrors.sessionAgenda = '';

        let hasErrors = false;

        if (!this.currentSession.title || !this.currentSession.title.trim()) {
            this.validationErrors.sessionTitle = 'Session title is required';
            hasErrors = true;
        }

        if (!this.currentSession.startTime) {
            this.validationErrors.sessionStartTime = 'Start time is required';
            hasErrors = true;
        }

        if (!this.currentSession.endTime) {
            this.validationErrors.sessionEndTime = 'End time is required';
            hasErrors = true;
        }

        const agendaValue = this.currentSession.agenda ? this.currentSession.agenda.trim() : '';
        if (!agendaValue) {
            this.validationErrors.sessionAgenda = 'Session agenda is required';
            hasErrors = true;
        } else if (agendaValue.length > 255) {
            this.validationErrors.sessionAgenda = 'Session agenda must not exceed 255 characters';
            hasErrors = true;
        }

        if (!this.currentSession.locationType) {
            this.validationErrors.locationType = 'Location type is required';
            hasErrors = true;
        }

        const normalizedStartTime = this.normalizeTimeForApex(this.currentSession.startTime);
        const normalizedEndTime = this.normalizeTimeForApex(this.currentSession.endTime);

        if (normalizedStartTime && normalizedEndTime) {
            const startTime = this.timeToMinutes(normalizedStartTime);
            const endTime = this.timeToMinutes(normalizedEndTime);

            if (endTime <= startTime) {
                this.validationErrors.timeRange = 'End time must be later than start time';
                hasErrors = true;
            }
        }

        this.validateLocationFields();
        if (this.validationErrors.eventLink || this.validationErrors.venueAddress) {
            hasErrors = true;
        }

        this.validationErrors = { ...this.validationErrors };

        if (hasErrors) {
            this.showToast('Error', 'Please fill all required fields and fix validation errors', 'error');
            return;
        }

        // A session MUST have a date — it is grouped by date for display, and a
        // date-less session is silently dropped by processEventScheduleData(). Use
        // the active date tab, falling back to the first selected event date.
        const resolvedSessionDate = this.activeDateTab
            || (this.selectedDates && this.selectedDates.length ? this.selectedDates[0].key : '');
        if (!resolvedSessionDate) {
            this.showToast('Error', 'Please select a date for the session before saving.', 'error');
            return;
        }
        this.activeDateTab = resolvedSessionDate;

        // Recover the event id if the in-memory value was lost (e.g. page refresh
        // while continuing a draft). Without it the Apex throws "Event ID is required".
        let resolvedEventId = this.currentEventId || this._recordId;
        if (!resolvedEventId) {
            try { resolvedEventId = sessionStorage.getItem('currentEventId'); } catch (e) { /* ignore */ }
        }
        if (!resolvedEventId) {
            this.showToast('Error', 'Event details must be saved before adding sessions.', 'error');
            return;
        }
        this.currentEventId = resolvedEventId;

        try {
            this.showSpinner = true;

            const sessionWrapper = {
                Id: this.currentSession.id || null,
                name: this.currentSession.title,
                agenda: this.currentSession.agenda,
                startDate: resolvedSessionDate,
                startTime: normalizedStartTime || null,
                endTime: normalizedEndTime || null,
                eventId: resolvedEventId,
                locationType: this.currentSession.locationType,
                locationAddress: this.currentSession.venueAddress,
                sessionLink: this.currentSession.eventLink,
                sessionBroucher: this.currentSession.brochure,
                brochureFileName: this.currentSession.brochureFileName || 'session-brochure.pdf',
                broucherFileType: this.currentSession.brochureFileType || '',
                noFee: this.currentSession.noFee === true, 
                isPortal: true,
                speakers: this.currentSession.speakers.map(speaker => ({
                    Id: speaker.id || null,
                    name: speaker.name,
                    email: speaker.email || null,
                    sendInvite: speaker.sendInvite === true,
                    description: speaker.description,
                    speakerImage: speaker.image,
                    speakerImageFileName: speaker.imageFileName
                }))
            };

            await createEventSchedule({ records: JSON.stringify([sessionWrapper]) });

            await refreshApex(this.wiredEventScheduleResponse);
            this.pendingNewSession = null;
            this.showSessionForm = false;
            this.editingSessionId = null;
            this.resetCurrentSession();

            this.showToast('Success', 'Session saved successfully', 'success');
        } catch (error) {
            this.showToast('Error', 'Failed to save session', 'error');
        } finally {
            this.showSpinner = false;
        }
    }

    handleAddSpeaker() {
        this.showSpeakerForm = true;
        this.editingSpeakerId = null;
        this.resetCurrentSpeaker();
    }

    handleEditSpeaker(event) {
        event.preventDefault();
        event.stopPropagation();

        const speakerId = event?.detail?.speakerId || event?.currentTarget?.dataset?.speakerId;
        if (!speakerId) {
            return;
        }

        const speaker = this.currentSession.speakers.find(s => s.uniqueId === speakerId);
        if (speaker) {
            this.editingSpeakerId = speakerId;
            const imageFileName = speaker.imageFileName || this.getSpeakerImageFileName(speaker.image);
            this.currentSpeaker = { ...speaker, imageFileName };
            this.showSpeakerForm = true; // Show modal for editing
        }
    }

    handleCloseSpeakerModal(event) {
        if (!event || event.target === event.currentTarget || event.currentTarget.classList.contains('speaker-modal-close')) {
            this.showSpeakerForm = false;
            this.editingSpeakerId = null;
            this.resetCurrentSpeaker();
        }
    }

    handleToggleSession(event) {
        event.stopPropagation();
        const sessionId = event.currentTarget.dataset.sessionId;
        const sessions = this.sessionsByDate[this.activeDateTab]?.sessions || [];
        const sessionIndex = sessions.findIndex(s => s.uniqueId === sessionId);
        
        if (sessionIndex !== -1) {
            // Toggle expanded state
            if (sessions[sessionIndex].isExpanded === undefined) {
                sessions[sessionIndex].isExpanded = false;
            } else {
                sessions[sessionIndex].isExpanded = !sessions[sessionIndex].isExpanded;
            }
            // Force reactivity
            this.sessionsByDate = { ...this.sessionsByDate };
        }
    }

    handleDeleteSpeaker(event) {
        const speakerId = event?.detail?.speakerId || event?.currentTarget?.dataset?.speakerId;
        if (!speakerId) {
            return;
        }
        this.currentSession.speakers = this.currentSession.speakers.filter(s => s.uniqueId !== speakerId);
    }

    handleDiscardSpeaker() {
        this.showSpeakerForm = false;
        this.editingSpeakerId = null;
        this.resetCurrentSpeaker();
    }

    handleDiscardSession() {
        // If editing a session inline, collapse its card without committing changes
        if (this.editingSessionId) {
            const dateKey = this.activeDateTab;
            const dateSessions = this.sessionsByDate[dateKey];
            if (dateSessions) {
                this.sessionsByDate = {
                    ...this.sessionsByDate,
                    [dateKey]: {
                        ...dateSessions,
                        sessions: dateSessions.sessions.map(s =>
                            s.uniqueId === this.editingSessionId ? { ...s, isExpanded: false } : s
                        )
                    }
                };
            }
        }
        this.pendingNewSession = null;
        this.showSessionForm = false;
        this.editingSessionId = null;
        this.editingSpeakerId = null;
        this.resetCurrentSession();
    }

    handleDiscardSessionEdit() {
        this.editingSessionId = null;
        this.editingSpeakerId = null;
        this.resetCurrentSession();
    }
    //
    async handleSubmitRequest() {
        const editingId = this.currentSession?.uniqueId;
        const dateSessions = this.sessionsByDate[this.activeDateTab];
        if (editingId && dateSessions && dateSessions.sessions.some(s => s.uniqueId === editingId)) {
            this._commitCurrentCard();
        }

        if (!this._validateAllSessionsAndFocus()) {
            this.showToast('Error', 'Please complete all session details before proceeding', 'error');
            return;
        }

        if (!this.validateStep3()) {
            return;
        }

        try {
            this.showSpinner = true;

            // Resolve the event ID (required by Apex)
            let resolvedEventId = this.currentEventId || this._recordId;
            if (!resolvedEventId) {
                try { resolvedEventId = sessionStorage.getItem('currentEventId'); } catch (e) { /* ignore */ }
            }
            if (!resolvedEventId) {
                this.showToast('Error', 'Event details must be saved before adding sessions.', 'error');
                return;
            }
            this.currentEventId = resolvedEventId;

            // Build wrappers for every session across all dates and save in one batch
            const allSessionWrappers = [];
            Object.entries(this.sessionsByDate).forEach(([dateKey, { sessions }]) => {
                (sessions || []).forEach(session => {
                    const normalizedStartTime = this.normalizeTimeForApex(session.startTime);
                    const normalizedEndTime = this.normalizeTimeForApex(session.endTime);
                    allSessionWrappers.push({
                        Id: session.id || null,
                        name: session.title,
                        agenda: session.agenda,
                        startDate: dateKey,
                        startTime: normalizedStartTime || null,
                        endTime: normalizedEndTime || null,
                        eventId: resolvedEventId,
                        locationType: session.locationType,
                        locationAddress: session.venueAddress || '',
                        sessionLink: session.eventLink || '',
                        sessionBroucher: session.brochure || null,
                        brochureFileName: session.brochureFileName || 'session-brochure.pdf',
                        broucherFileType: session.brochureFileType || '',
                        noFee: session.noFee !== false,
                        isPortal: true,
                        speakers: (session.speakers || []).map(speaker => ({
                            Id: speaker.id || null,
                            name: speaker.name,
                            email: speaker.email || null,
                            sendInvite: speaker.sendInvite === true,
                            description: speaker.description || '',
                            speakerImage: speaker.image || null,
                            speakerImageFileName: speaker.imageFileName || ''
                        }))
                    });
                });
            });

            if (allSessionWrappers.length > 0) {
                await createEventSchedule({ records: JSON.stringify(allSessionWrappers) });
            }

            this._clearSessionsFromLocalStorage();

            await refreshApex(this.wiredEventScheduleResponse);

            try {
                await this.saveEventData(3);
            } catch (error) {
                console.error('Error saving step 3, but proceeding anyway:', error);
            }

            this.isStep3Completed = true;
            this.buildFeeRowsFromSessions();
            this.buildFeedbackForms();
            await this.loadSurveyIfNeeded();
            this.currentStep = 4;
            this.showToast('Success', 'Proceeding to pre-event surveys', 'success');
        } catch (error) {
            console.error('Error in handleSubmitRequest, but proceeding anyway:', error);
            this.isStep3Completed = true;
            this.buildFeeRowsFromSessions();
            this.buildFeedbackForms();
            this.currentStep = 4;
        } finally {
            this.showSpinner = false;
        }
    }

    handleSurveyToggleMandatory(event) {
        this.surveyMandatory = event.target.checked;
    }

    async loadSurveyIfNeeded() {
        const eventId = this.currentEventId;
        if (!eventId || this._surveyLoadedForEventId === eventId) {
            return;
        }
        this._surveyLoadedForEventId = eventId;

        try {
            const questionnaire = await getQuestionnaireByEventId({ eventId });
            if (!questionnaire) {
                return;
            }
            this.surveyQuestionnaireId = questionnaire.Id;
            const params = questionnaire.Ken_Questionnaire_Parameters__r || [];
            const questions = params.map((qp, idx) => {
                const type = this.mapQuestionTypeFromPicklist(qp.Question_Type__c);
                const isLinear = type === 'linear';
                let options = [];
                if (type === 'multiple' || type === 'checkbox' || type === 'dropdown') {
                    options = this.parseOptionsFromServer(qp.MCQ_Options__c, qp.Id);
                    if (!options.length) {
                        options = this.defaultOptionsForType(qp.Id);
                    }
                }
                const linearConfig = this.parseLinearConfig(qp.MCQ_Options__c);
                return {
                    id: qp.Id,
                    number: idx + 1,
                    text: qp.Question_Label__c || '',
                    type: type,
                    required: !!qp.Is_Required__c,
                    options: options,
                    scaleMin: isLinear ? (linearConfig.scaleMin || '1') : '1',
                    scaleMax: isLinear ? (linearConfig.scaleMax || '5') : '5',
                    scaleMinLabel: isLinear ? (linearConfig.scaleMinLabel || '') : '',
                    scaleMaxLabel: isLinear ? (linearConfig.scaleMaxLabel || '') : ''
                };
            });
            if (questions.length) {
                this.surveyQuestions = questions;
                this.customSurveyEnabled = true;
            }
        } catch (error) {
            console.error('Error loading survey for event:', error);
        }
    }

    parseOptionsFromServer(rawOptions, questionId) {
        if (!rawOptions) return [];
        const values = String(rawOptions)
            .split(';')
            .map(v => v.trim())
            .filter(Boolean);
        return values.map((text, idx) => ({
            id: `${questionId}-opt-${idx + 1}`,
            text,
            letter: String.fromCharCode(97 + idx)
        }));
    }

    defaultOptionsForType(questionId) {
        return [
            { id: `${questionId}-opt-1`, text: '', letter: 'a' },
            { id: `${questionId}-opt-2`, text: '', letter: 'b' }
        ];
    }

    parseLinearConfig(rawConfig) {
        if (!rawConfig) return {};
        try {
            const parsed = JSON.parse(rawConfig);
            return parsed && typeof parsed === 'object' ? parsed : {};
        } catch (e) {
            return {};
        }
    }

    // Map server-side Ken_Questionnaire_Parameter__c records into the LWC question shape
    // (shared by survey + per-session feedback prepopulation).
    buildQuestionsFromParams(params) {
        if (!Array.isArray(params) || !params.length) {
            return [];
        }
        return params.map((qp, idx) => {
            const type = this.mapQuestionTypeFromPicklist(qp.Question_Type__c);
            const isLinear = type === 'linear';
            let options = [];
            if (type === 'multiple' || type === 'checkbox' || type === 'dropdown') {
                options = this.parseOptionsFromServer(qp.MCQ_Options__c, qp.Id);
                if (!options.length) {
                    options = this.defaultOptionsForType(qp.Id);
                }
            }
            const linearConfig = this.parseLinearConfig(qp.MCQ_Options__c);
            return {
                id: qp.Id,
                number: idx + 1,
                text: qp.Question_Label__c || '',
                type: type,
                required: !!qp.Is_Required__c,
                options: options,
                scaleMin: isLinear ? (linearConfig.scaleMin || '1') : '1',
                scaleMax: isLinear ? (linearConfig.scaleMax || '5') : '5',
                scaleMinLabel: isLinear ? (linearConfig.scaleMinLabel || '') : '',
                scaleMaxLabel: isLinear ? (linearConfig.scaleMaxLabel || '') : ''
            };
        });
    }

    handleSurveyQuestionChange(event) {
        const { questionId, value } = event.detail || {};
        if (!questionId) return;
        this.surveyQuestions = (this.surveyQuestions || []).map(q => q.id === questionId ? { ...q, text: value } : q);
    }

    handleSurveyTypeChange(event) {
        const { questionId, value } = event.detail || {};
        if (!questionId) return;

        this.surveyQuestions = this.surveyQuestions.map(q => {
            if (q.id !== questionId) return q;
            const needsOptions = value === 'multiple' || value === 'checkbox';
            const options = needsOptions ? (q.options && q.options.length ? q.options : [
                { id: `${questionId}-opt-1`, text: '', letter: 'a' },
                { id: `${questionId}-opt-2`, text: '', letter: 'b' }
            ]) : [];
            const isLinear = value === 'linear';
            return {
                ...q,
                type: value,
                options: options,
                hasOptions: options && options.length > 0,
                scaleMin: isLinear ? (q.scaleMin != null ? String(q.scaleMin) : '1') : (q.scaleMin || '1'),
                scaleMax: isLinear ? (q.scaleMax != null ? String(q.scaleMax) : '5') : (q.scaleMax || '5'),
                scaleMinLabel: isLinear ? (q.scaleMinLabel || '') : (q.scaleMinLabel || ''),
                scaleMaxLabel: isLinear ? (q.scaleMaxLabel || '') : (q.scaleMaxLabel || '')
            };
        });
    }

    handleSurveyScaleChange(event) {
        const { questionId, scaleMin, scaleMax, scaleMinLabel, scaleMaxLabel } = event.detail || {};
        if (!questionId) return;

        this.surveyQuestions = (this.surveyQuestions || []).map(q => {
            if (q.id !== questionId) return q;
            const updated = { ...q };
            if (scaleMin !== undefined) updated.scaleMin = scaleMin;
            if (scaleMax !== undefined) updated.scaleMax = scaleMax;
            if (scaleMinLabel !== undefined) updated.scaleMinLabel = scaleMinLabel;
            if (scaleMaxLabel !== undefined) updated.scaleMaxLabel = scaleMaxLabel;
            return updated;
        });
    }

    handleSurveyOptionChange(event) {
        const { questionId, optionId, value } = event.detail || {};
        if (!questionId || !optionId) return;

        this.surveyQuestions = this.surveyQuestions.map(q => {
            if (q.id !== questionId) return q;
            const options = (q.options || []).map(opt => opt.id === optionId ? { ...opt, text: value } : opt);
            return { ...q, options, hasOptions: options && options.length > 0 };
        });
    }

    handleSurveyAddOption(event) {
        const { questionId } = event.detail || {};
        if (!questionId) return;
        this.surveyQuestions = this.surveyQuestions.map(q => {
            if (q.id !== questionId) return q;
            const nextIndex = (q.options?.length || 0) + 1;
            const letter = String.fromCharCode(96 + nextIndex);
            const newOption = { id: `${questionId}-opt-${nextIndex}`, text: `Option ${nextIndex}`, letter };
            const updatedOptions = [...(q.options || []), newOption];
            return { ...q, options: updatedOptions, hasOptions: updatedOptions.length > 0 };
        });
    }

    handleSurveyRemoveQuestion(event) {
        const { questionId } = event.detail || {};
        if (!questionId) return;
        this.surveyQuestions = this.surveyQuestions
            .filter(q => q.id !== questionId)
            .map((q, idx) => ({ ...q, number: idx + 1 }));
    }

    handleSurveyRemoveOption(event) {
        const { questionId, optionId } = event.detail || {};
        if (!questionId || !optionId) return;
        this.surveyQuestions = (this.surveyQuestions || []).map(q => {
            if (q.id !== questionId) return q;
            const options = (q.options || []).filter(opt => opt.id !== optionId)
                .map((opt, idx) => ({ ...opt, letter: String.fromCharCode(97 + idx) }));
            return { ...q, options, hasOptions: options.length > 0 };
        });
    }

    handleSurveyReorderQuestions(event) {
        const { fromQuestionId, toQuestionId } = event.detail || {};
        if (!fromQuestionId || !toQuestionId || fromQuestionId === toQuestionId) return;

        const list = [...(this.surveyQuestions || [])];
        const fromIdx = list.findIndex(q => q.id === fromQuestionId);
        const toIdx = list.findIndex(q => q.id === toQuestionId);
        if (fromIdx === -1 || toIdx === -1) return;

        const [moved] = list.splice(fromIdx, 1);
        list.splice(toIdx, 0, moved);

        this.surveyQuestions = list.map((q, idx) => ({ ...q, number: idx + 1 }));
    }

    handleAddSurveyQuestion() {
        const nextNumber = this.surveyQuestions.length + 1;
        const questionId = `q-${Date.now()}`;
        const options = [
            { id: `${questionId}-opt-1`, text: '', letter: 'a' },
            { id: `${questionId}-opt-2`, text: '', letter: 'b' }
        ];
        this.surveyQuestions = [
            ...this.surveyQuestions,
            {
                id: questionId,
                number: nextNumber,
                text: '',
                type: 'multiple',
                required: false,
                options: options,
                hasOptions: options.length > 0
            }
        ];
    }

    async handleSaveSurveyProceed() {
        // Dietary preferences are required when meals are offered. Block proceed and surface the
        // inline error in the survey component if they haven't been chosen.
        const surveyCmp = this.template.querySelector('c-ken-pre-event-survey');
        if (surveyCmp && typeof surveyCmp.validate === 'function' && !surveyCmp.validate()) {
            // Surface the actual reason (blank question / missing options / dietary),
            // not a hardcoded dietary message.
            const msg = surveyCmp.validationMessage || 'Please complete the required survey fields before proceeding.';
            this.showToast('Error', msg, 'error');
            return;
        }

        try {
            this.showSpinner = true;

            // Persist meals (sessions) + dietary / meal-paid flags (event)
            try {
                if (this.currentEventId) {
                    await savePreEventSurveyData({
                        eventId: this.currentEventId,
                        offerMeals: !!this.surveyMealsData?.offerMealsEnabled,
                        makeMealsPaid: !!this.surveyMealsData?.mealsPaidAddonEnabled,
                        collectDietary: !!this.surveyMealsData?.dietaryEnabled,
                        dietaryPreferences: (this.surveyMealsData?.dietaryOptions || []).join(';'),
                        mealsByDateJson: JSON.stringify(this.surveyMealsData?.mealsByDate || {})
                    });
                }
            } catch (error) {
                console.error('Error saving meal/dietary data, but proceeding anyway:', error);
            }

            // Only persist a questionnaire when the custom survey is enabled and has questions
            if (!this.customSurveyEnabled || !(this.surveyQuestions && this.surveyQuestions.length)) {
                this.isStep4Completed = true;
                if (this.feeDisabled) {
                    this.isStep5Completed = true;
                    this.currentStep = 6;
                    this.showToast('Success', 'Proceeding to feedback form', 'success');
                } else {
                    this.currentStep = 5;
                    this.showToast('Success', 'Proceeding to fee setup', 'success');
                }
                return;
            }

            const questionnaire = {
                Id: this.surveyQuestionnaireId || null,
                Section_Name__c: `${this.eventData.title || 'Event'} Survey`,
                Descripation__c: 'Registration survey',
                Target_Audience__c: this.selectedSuitableFor.map(item => item.value).join(';')
            };

            const questionsPayload = this.surveyQuestions.map(q => {
                const isLinear = q.type === 'linear';
                const MCQ_Options__c = isLinear
                    ? JSON.stringify({
                        scaleMin: q.scaleMin != null ? String(q.scaleMin) : '1',
                        scaleMax: q.scaleMax != null ? String(q.scaleMax) : '5',
                        scaleMinLabel: q.scaleMinLabel || '',
                        scaleMaxLabel: q.scaleMaxLabel || ''
                    })
                    : (q.options || []).map(opt => opt.text).join(';');
                return {
                    Id: q.Id || null,
                    Question_Label__c: q.text,
                    Question_Type__c: this.mapQuestionTypeForPicklist(q.type),
                    Is_Required__c: q.required || false,
                    MCQ_Options__c
                };
            });

            try {
                const questionnaireId = await saveQuestionnaireForEvent({
                    eventId: this.currentEventId,
                    questionnaire,
                    questions: questionsPayload
                });
                this.surveyQuestionnaireId = questionnaireId;
            } catch (error) {
                console.error('Error saving survey, but proceeding anyway:', error);
            }

            this.isStep4Completed = true;
            if (this.feeDisabled) {
                this.isStep5Completed = true;
                this.currentStep = 6;
                this.showToast('Success', 'Proceeding to feedback form', 'success');
            } else {
                this.currentStep = 5;
                this.showToast('Success', 'Proceeding to fee setup', 'success');
            }
        } catch (error) {
            console.error('Error in handleSaveSurveyProceed, but proceeding anyway:', error);
            this.isStep4Completed = true;
            if (this.feeDisabled) {
                this.isStep5Completed = true;
                this.currentStep = 6;
            } else {
                this.currentStep = 5;
            }
        } finally {
            this.showSpinner = false;
        }
    }

    mapQuestionTypeForPicklist(typeValue) {
        if (!typeValue) return typeValue;
        const normalized = String(typeValue).toLowerCase();
        if (normalized === 'multiple') return 'Multiple Choice';
        if (normalized === 'checkbox') return 'Yes/No';
        if (normalized === 'linear') return 'Linear Scale';
        if (normalized === 'short' || normalized === 'text') return 'Short Answer';
        if (normalized === 'dropdown') return 'Dropdown';
        if (normalized === 'comment') return 'Comment';
        if (normalized === 'file upload' || normalized === 'fileupload') return 'File Upload';
        if (normalized === 'rating') return 'Rating';
        return typeValue;
    }

    mapQuestionTypeFromPicklist(typeValue) {
        if (!typeValue) return typeValue;
        const normalized = String(typeValue).toLowerCase();
        if (normalized === 'multiple choice') return 'multiple';
        if (normalized === 'yes/no') return 'checkbox';
        if (normalized === 'linear scale') return 'linear';
        if (normalized === 'short answer') return 'short';
        if (normalized === 'dropdown') return 'dropdown';
        if (normalized === 'comment') return 'comment';
        if (normalized === 'file upload') return 'fileupload';
        if (normalized === 'rating') return 'rating';
        return typeValue;
    }

    mapFeedbackTriggerTypeToDb(value) {
        if (!value) return value;
        const normalized = String(value).toLowerCase();
        if (normalized === 'auto' || normalized === 'auto-trigger') return 'Auto-trigger';
        if (normalized === 'manual' || normalized === 'trigger manually after session') {
            return 'Trigger manually after session';
        }
        return value;
    }

    mapFeedbackTriggerTypeFromDb(value) {
        if (!value) return null;
        const normalized = String(value).toLowerCase();
        if (normalized === 'auto-trigger') return 'auto';
        if (normalized === 'trigger manually after session') return 'manual';
        return value;
    }

    mapFeedbackTriggerWhenToDb(value) {
        if (!value) return value;
        const normalized = String(value).toLowerCase();
        if (normalized === 'custom' || normalized === 'custom date & time') return 'Custom date & time';
        if (normalized === 'session_end' || normalized === 'at session end') return 'At Session end';
        return value;
    }

    mapFeedbackTriggerWhenFromDb(value) {
        if (!value) return null;
        const normalized = String(value).toLowerCase();
        if (normalized === 'custom date & time') return 'custom';
        if (normalized === 'at session end') return 'session_end';
        return value;
    }

    isSalesforceId(value) {
        return typeof value === 'string' && /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(value);
    }

    handleSkipStep() {
        if (this.currentStep < 7) {
            this.currentStep += 1;
        }
    }

    // Step 6 (Feedback Form) -> Step 7 (Summary)
    async handleProceedFromFeedback() {
        const hasMissingFeedback = this.feedbackFormsByDate.some(day =>
            day.sessions.some(session => !session.hasForm)
        );
        if (hasMissingFeedback) {
            this.showMissingFeedbackModal = true;
            return;
        }

        try {
            this.showSpinner = true;
            // Batch-save all feedback configurations that were stored in memory
            const savePromises = Object.entries(this.feedbackDataBySession).map(([sessionId, data]) => {
                const triggerTypeDb = this.mapFeedbackTriggerTypeToDb(data.triggerType);
                const triggerWhenDb = this.mapFeedbackTriggerWhenToDb(data.triggerWhen);
                return Promise.all([
                    this.persistFeedbackTriggerSettings(sessionId, triggerTypeDb, triggerWhenDb, data.endDate, data.endTime),
                    this.persistFeedbackQuestionnaire(sessionId, data.questions || [])
                ]);
            });
            await Promise.all(savePromises);
        } catch (error) {
            console.error('Error saving feedback on proceed:', error);
        } finally {
            this.showSpinner = false;
        }

        this.goToSummary();
    }

    goToSummary() {
        this.isStep6Completed = true;
        this.currentStep = 7;
    }

    // Summary step "Edit" links jump back to the relevant step
    handleEditStep(event) {
        const step = event?.detail?.step;
        // The Fee Setup step (5) is not reachable when fees are disabled.
        if (this.feeDisabled && step === 5) {
            return;
        }
        if (step && step >= 1 && step <= 7) {
            this.closeAllDropdowns();
            this.currentStep = step;
        }
    }

    async handleFinalizeEvent() {
        // Final submit happens only from the Summary step.
        if (this.currentStep !== 7) {
            return;
        }
        this.isStep7Completed = true;
        await this.handleSubmitTriggeringFeedback();
    }

     navigateToHome() {
        const isPortal = !!this.cBasePath;
        if (isPortal) {
            // Experience/portal context: the internal object list view doesn't exist here and would
            // land on an error page, so route to the community Hosted Events page (/hosted-events).
            this.navigateToHostedEvents();
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Ken_Event_Master__c',
                actionName: 'list'
            },
            state: {
                filterName: 'Active_EVents'
            }
        }, true);
    }


    // Save as Draft (available on the Summary step)
    async handleSaveAsDraft() {
        try {
            this.showSpinner = true;
            // Best-effort save (no blocking)
            try {
                await this.saveEventData(this.currentStep, { suppressToast: true });
            } catch (error) {
                console.error('Error saving draft, but continuing anyway:', error);
            }
            sessionStorage.removeItem('currentEventId');
            this.showToast('Success', 'Draft saved', 'success');
        } catch (error) {
            console.error('Error in handleSaveAsDraft:', error);
        } finally {
            this.showSpinner = false;
        }
    }

    async handleSaveFeedbackProceed() {
        try {
            await this.handleFinalizeEvent();
        } catch (error) {
            console.error('Error in handleSaveFeedbackProceed:', error);
        }
    }

    handleGoBackFromMissingFeedback() {
        this.showMissingFeedbackModal = false;
    }

    handleContinueAnyway() {
        this.showMissingFeedbackModal = false;
        this.goToSummary();
    }

    handleCancelTriggeringFeedback() {
        this.showTriggeringFeedbackModal = false;
    }

    handleTriggerTypeChange(event) {
        this.triggerType = event.target.value;
    }

    handleTriggerWhenChange(event) {
        this.triggerWhen = event.target.value;
    }

    async handleSubmitTriggeringFeedback() {
        try {
            this.showSpinner = true;
            this.showTriggeringFeedbackModal = false;
            try {
                await this.saveEventData(7, { suppressToast: true, submit: true });
            } catch (error) {
                console.error('Error saving final submission, but proceeding anyway:', error);
            }
            this.isStep7Completed = true;
            sessionStorage.removeItem('currentEventId');
            this.showToast('Success', 'Event process completed', 'success');
            setTimeout(() => {
                // Reset right before navigating away so a reused component instance
                // (portal SPA nav, or the admin "New" record action) never carries this
                // event's data into the next "Host Event"/"New" entry.
                this.resetForm();
                this.navigateToHome();
            }, 3000);
        } catch (error) {
            console.error('Error in handleSubmitTriggeringFeedback, but proceeding anyway:', error);
            this.isStep7Completed = true;
            sessionStorage.removeItem('currentEventId');
            this.resetForm();
        } finally {
            this.showSpinner = false;
        }
    }

    get isAutoTriggerSelected() {
        return this.triggerType === 'auto';
    }

    get isManualTriggerSelected() {
        return this.triggerType === 'manual';
    }
    //
    async handleEmailConfirmYes() {
        this.showEmailConfirmModal = false;
        //  try {
        //     this.showSpinner = true;

        //     await this.saveEventData(3);

        //     this.isStep3Completed = true;
        //     sessionStorage.removeItem('currentEventId');

        //     setTimeout(() => {
        //         this.navigateToHostedEvents();
        //     }, 500);
        // } catch (error) {
        //     console.error('Error submitting event:', error);
        //     this.showToast('Error', 'Failed to submit event', 'error');
        // } finally {
        //     this.showSpinner = false;
        // }
        this.showShareEmailModal = true;
    }

    handleEmailConfirmNo() {
        this.showEmailConfirmModal = false;
        // this.submitRequest(false);
        // this.handleSaveSession();
        this.handleSubmitShareEmail();
        // handleSaveAndProceed();
        setTimeout(() => {
            this.navigateToHostedEvents();
        }, 500);
    }
    handleCloseEmailConfirmModal() {
        this.showEmailConfirmModal = false;

    }

    handleCloseShareEmailModal() {
        this.showShareEmailModal = false;
        this.selectedEmailDistributionList = [];
        this.scheduleDate = '';
        this.shareEmailTime = '';
        this.emailBody = '';
        this.emailAttachments = [];
        this.subjectError = '';
        this.bodyError = '';
        this.shareEmailSubject = '';
    }



    handleShareEmailSubjectChange(event) {
        this.shareEmailSubject = event.target.value;

        if (this.shareEmailSubject.length > 80) {
            this.subjectError = 'Subject cannot exceed 80 characters.';
        } else {
            this.subjectError = '';
        }
    }

    handleShareEmailBodyChange(event) {
        this.shareEmailBody = event.target.value;

        if (this.shareEmailBody.length > 5000) {
            this.bodyError = 'Email body cannot exceed 5000 characters.';
        } else {
            this.bodyError = '';
        }
    }
    handleScheduleDateChange(event) {
        console.log(event.target.value, 'valuedateee');

        this.scheduleDate = event.target.value;
    }
    handleScheduleTimeChange(event) {
        this.shareEmailTime = event.target.value;
    }
    handleShareEmailAttachmentChange(event) {
        const file = event.target.files[0];
        if (file) {
            const reader = new FileReader();
            reader.onload = (e) => {
                this.shareEmailAttachment = e.target.result;
            };
            reader.readAsDataURL(file);
        }
    }
    async handleSubmitShareEmail() {

        try {
            this.showSpinner = true;
            this.emailBody = this.shareEmailBody;
            this.emailSubject = this.shareEmailSubject;
            this.emailAttachment = this.shareEmailAttachment;
            this.scheduleTime = this.shareEmailTime
            // Build the payload for Apex
            const emailData = {
                Id: this.currentEventId,
                emailSubject: this.shareEmailSubject,
                emailBody: this.shareEmailBody,
                emailDistributionList: this.selectedEmailDistributionList.map(item => item.value).join(';'),
                emailDate: this.scheduleDate,
                emailTime: this.shareEmailTime,
                emailAttachment: this.shareEmailAttachment
            };

            // Call Apex to save the data (update your Apex method to accept these fields)
            this.saveEventData(3);

            this.isStep3Completed = true;
            this.showShareEmailModal = false;
            sessionStorage.removeItem('currentEventId');
            setTimeout(() => {
                this.navigateToHostedEvents();
            }, 500);
        } catch (error) {
            this.showToast('Error', 'Failed to save email details', 'error');
        } finally {
            this.showSpinner = false;
        }
    }

    navigateToHostedEvents() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'hosted_events__c'
            }
        }, true);
    }

    // Utility methods
    generateCalendar() {
        const year = this.currentDate.getFullYear();
        const month = this.currentDate.getMonth();
        const firstDay = new Date(year, month, 1);
        const lastDay = new Date(year, month + 1, 0);
        const startDate = new Date(firstDay);
        startDate.setDate(startDate.getDate() - firstDay.getDay());

        this.calendarDays = [];

        // Get today's date in local timezone
        const today = new Date();
        const todayLocal = new Date(today.getFullYear(), today.getMonth(), today.getDate());

        for (let i = 0; i < 42; i++) {
            const date = new Date(startDate);
            date.setDate(startDate.getDate() + i);

            // Create date string in YYYY-MM-DD format
            const year = date.getFullYear();
            const month = String(date.getMonth() + 1).padStart(2, '0');
            const day = String(date.getDate()).padStart(2, '0');
            const dateStr = `${year}-${month}-${day}`;

            const isSelected = this.selectedDates.some(d => d.value === dateStr);

            // Compare dates properly (only past dates should be disabled)
            const compareDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
            const isDisabled = compareDate < todayLocal;

            const isOtherMonth = date.getMonth() !== month - 1; // month is 0-indexed

            let classes = 'calendar-day';
            if (isSelected) classes += ' selected';
            if (isDisabled) classes += ' disabled';
            if (isOtherMonth) classes += ' other-month';

            this.calendarDays.push({
                key: dateStr,
                day: date.getDate(),
                date: dateStr,
                selected: isSelected,
                disabled: isDisabled,
                otherMonth: isOtherMonth,
                classes: classes
            });
        }
    }

    initializeSessionsByDate() {
        this.sessionsByDate = {};
        this.selectedDates.forEach(date => {
            this.sessionsByDate[date.key] = { sessions: [] };
        });
    }

    resetForm() {
        // Always close dropdowns when resetting form
        this.closeAllDropdowns();

        sessionStorage.removeItem('currentEventId');
        this.currentEventId = null;
        this.isEditMode = false;
        this.eventData = {
            title: '',
            categories: [],
            maxParticipants: '',
            description: '',
            expectations: '',
            targetAudienceApplicable: [],
            languages: [],
            brochure: null,
            broucherFileName: '',
            speakers: [],
            noFee: true,
            coverImage: '',
            coverImageFileName: '',
            agenda: '',
            // Must match the initial declaration AND the rendered defaults —
            // the radio shows "Yes" and the stepper shows 1, so the data must
            // say so too or save-validation fails until the user touches them.
            canBringGuests: 'yes',
            maxGuestsPerParticipant: 1
        };
        this.selectedDates = [];
        this.sessionsByDate = {};
        this.selectedCategories = [];
        this.selectedSuitableFor = [];
        this.selectedLanguages = [];
        this.selectedAudienceData = [];
        this.isStep1Completed = false;
        this.isStep2Completed = false;
        this.isStep3Completed = false;
        this.isStep4Completed = false;
        this.isStep5Completed = false;
        this.isStep6Completed = false;
        this.isStep7Completed = false;

        // Later-step state must clear too, otherwise a reused component instance carries the previous
        // event's schedule/fee/survey/feedback into the next "Host Event".
        this.currentStep = 1;
        this.feeRowsByDate = [];
        this.feeSummaryTotal = 0;
        this.feeSummarySessions = [];
        this.pricingMode = null;
        this.overallPrice = '';
        this.overallIsFree = false;
        this.mealFees = '';
        this.surveyMandatory = false;
        this.surveyQuestionnaireId = '';
        this.surveyMealsData = { mealsPaidAddonEnabled: false };
        this.customSurveyEnabled = false;
        this.feedbackFormsByDate = [];
        this.feedbackDataBySession = {};
        this.activeFeedbackSessionId = null;
        this.triggerType = 'auto';
        this.triggerWhen = '';
        this.resetCurrentSession();
        this.resetCurrentSpeaker();
    }

    resetCurrentSession() {
        this.currentSession = {
            id: null,
            title: '',
            startTime: '',
            endTime: '',
            agenda: '',
            locationType: '',
            eventLink: '',
            venueAddress: '',
            brochure: null,
            sessionBroucher: null,
            brochureFileName: '',
            brochureFileType: '',
            speakers: []
        };

        const textarea = this.template.querySelector('[data-id="emptySessionAgenda"]');
        if (textarea && textarea.value !== (this.currentSession.agenda || '')) {
            textarea.value = this.currentSession.agenda || '';
        }

        this.validationErrors = {
            sessionTitle: '',
            sessionStartTime: '',
            sessionEndTime: '',
            timeRange: '',
            sessionAgenda: '',
            locationType: '',
            eventLink: '',
            sessionBrochure: '',
            venueAddress: ''
        };

        this.validationErrors = { ...this.validationErrors };
    }

    resetCurrentSpeaker() {
        this.currentSpeaker = {
            name: '',
            email: '',
            sendInvite: false,
            image: null,
            imageFileName: '',
            description: ''
        };
    }

    generateUniqueId() {
        return Date.now().toString() + '_' + Math.random().toString(36).substr(2, 9);
    }
    handletest() {
        this.showShareEmailModal = true;
    }
}