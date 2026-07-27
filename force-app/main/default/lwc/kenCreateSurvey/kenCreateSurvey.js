import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

// `@salesforce/community/basePath` only resolves inside Experience Cloud; importing
// it in a Lightning Experience host (action override / app page) makes the whole
// LWC silently fail to load. We compute the context at runtime instead.
const PATHNAME = (() => {
    try {
        return (typeof window !== 'undefined' && window.location && window.location.pathname)
            ? window.location.pathname : '';
    } catch (e) {
        return '';
    }
})();
// Admin = running inside the Lightning Experience shell (action override / app page),
// whose URLs live under `/lightning/...`. Everything else is an Experience Cloud portal.
// IMPORTANT: do NOT detect the portal via `/s/` — that only exists on Aura sites. LWR
// sites use clean URLs (e.g. `/alumni/create-survey`), so a `/s/` check misfires and makes
// the portal look like admin (wrong layout height + wrong cancel/redirect navigation).
const IS_ADMIN_CONTEXT = PATHNAME.indexOf('/lightning/') !== -1;
// Community base path (leading site segment), used only for fallback URL navigation.
const basePath = (() => {
    if (IS_ADMIN_CONTEXT || !PATHNAME) return '';
    const sIdx = PATHNAME.indexOf('/s/');
    if (sIdx > -1) return PATHNAME.substring(0, sIdx); // Aura site
    const seg = PATHNAME.split('/').filter((s) => s);  // LWR site → first path segment
    return seg.length ? '/' + seg[0] : '';
})();
import SURVEY_OBJECT from '@salesforce/schema/Ken_Survey__c';
import SURVEY_TARGET_FIELD from '@salesforce/schema/Ken_Survey__c.Target_Audience__c';
import QUESTION_OBJECT from '@salesforce/schema/Ken_Questionnaire_Parameter__c';
import QUESTION_TYPE_FIELD from '@salesforce/schema/Ken_Questionnaire_Parameter__c.Question_Type__c';
import createSurveyWithQuestions from '@salesforce/apex/KenSurveyController.createSurveyWithQuestions';
import updateSurveyWithQuestions from '@salesforce/apex/KenSurveyController.updateSurveyWithQuestions';
import saveSurveyDraft from '@salesforce/apex/KenSurveyController.saveSurveyDraft';
import getSurveyForEdit from '@salesforce/apex/KenSurveyController.getSurveyForEdit';
import getLinkedSegmentation from '@salesforce/apex/KenAudienceJunctionController.getLinkedSegmentation';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
const DRAFT_STORAGE_KEY = 'createSurveyDraft';
const SURVEY_ID_STORAGE_KEY = 'createSurveySurveyId';
const ALLOWED_QUESTION_TYPES = ['multiple', 'checkbox', 'linear', 'short'];
const QUESTION_TYPE_LABELS = {
    multiple: 'Single Select',
    checkbox: 'Checkbox',
    linear: 'Linear Scale',
    short: 'Short Answer'
};

export default class KenCreateSurvey extends NavigationMixin(LightningElement) {
    @track savedRecordId;
    @track showSuccessModal = false;
    @track showErrorModal = false;
    @track successTitle = '';
    @track successDescription = '';
    @track errorTitle = '';
    @track errorDescription = '';
    successTimeout;
    errorTimeout;
    redirectTimeout;
    @track showSuccessLoader = false;
    @track surveyTitle = '';
    @track surveyDescription = '';
    @track targetAudience = [];
    @track selectedAudienceData = [];
    @track startDate = '';
    @track endDate = '';
    @track titleError = '';
    @track startDateError = '';
    @track endDateError = '';
    @track showAudienceDropdown = false;
    @track enableAnonymous = false;
    @track currentStep = 1;
    @track isStep1Completed = false;
    @track isStep2Completed = false;
    @track isStep3Completed = false;
    @track isStep4Completed = false;
    @track isGroup1Expanded = true;
    @track audienceSummaryExpandedMap = {};
    styleElement = null;
    @track editSurveyId = null;
    // True when the LWC is hosted outside of Experience Cloud (System Admin / Lightning app).
    // basePath is the empty string in internal contexts, '/<siteUrlPath>' on a community page.
    isAdminContext = IS_ADMIN_CONTEXT;
    // Portal access gate — hides the form behind an opaque overlay until we confirm
    // "Allow Create Survey" is on, so it never flashes before a redirect.
    @track checkingAccess = false;
    @track accessDenied = false;
    // recordId comes from the Aura action-override wrapper (editSurveyForm.cmp). When present
    // we treat the LWC as in edit mode for that survey and load existing data from Apex.
    _recordId;
    _hydratedRecordId;
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.editSurveyId = value;
            this.savedRecordId = value;
            // Defer the actual hydration to connectedCallback / loadSurveyFromServer so
            // we don't double-fetch when sessionStorage already holds the same draft.
        }
    }
    @track questions = [
        {
            id: '1',
            number: 1,
            text: '',
            type: '',
            required: false,
            options: [],
            scaleMin: '1',
            scaleMax: '5',
            scaleMinLabel: '',
            scaleMaxLabel: '',
            showMultipleOptions: false,
            isMultiple: false,
            isCheckboxType: false,
            showLinearScale: false,
            showShortAnswer: false,
            nextOptionNumber: 1,
            hasInsufficientOptions: false,
            cannotDeleteOption: false
        }
    ];
    @track targetAudienceOptionsData = [];
    @track questionTypeOptionsData = [];

    @wire(getObjectInfo, { objectApiName: SURVEY_OBJECT })
    surveyObjectInfo;

    @wire(getObjectInfo, { objectApiName: QUESTION_OBJECT })
    questionObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$surveyObjectInfo.data.defaultRecordTypeId',
        fieldApiName: SURVEY_TARGET_FIELD
    })
    wiredAudiencePicklist({ data, error }) {
        if (data) {
            this.targetAudienceOptionsData = data.values.map(val => ({
                label: val.label,
                value: val.value,
                selected: this.targetAudience.includes(val.value)
            }));
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading audience picklist', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$questionObjectInfo.data.defaultRecordTypeId',
        fieldApiName: QUESTION_TYPE_FIELD
    })
    wiredQuestionTypePicklist({ data, error }) {
        if (data) {
            this.questionTypeOptionsData = this.buildQuestionTypeOptions(data.values);
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading question type picklist', error);
            this.questionTypeOptionsData = [];
        }
    }

    // Theme + outside-click listener + draft hydration all live in the single
    // connectedCallback defined further below. The previous duplicate `connectedCallback`
    // here was silently overwritten by JS class semantics — the merged version handles
    // everything (theme, outside click, draft load, admin record hydration).

    // Root + container classes — the portal CSS uses `100vh - 148px` calcs that
    // assume the community shell. Inside the Salesforce action override the host
    // gives us a different scrollable region, so we toggle an `is-admin` modifier
    // that resets height to natural in CSS.
    get rootClass() {
        return this.isAdminContext ? 'create-survey-page is-admin' : 'create-survey-page';
    }

    get containerClass() {
        return this.isAdminContext ? 'component-container is-admin' : 'component-container';
    }

    get targetAudienceOptions() {
        return (this.targetAudienceOptionsData || []).map(opt => ({
            ...opt,
            selected: this.targetAudience.includes(opt.value)
        }));
    }

    get hasSelectedAudience() {
        // Check if selectedAudienceData exists and has items (required to allow next step)
        if (!this.selectedAudienceData) {
            return false;
        }
        if (Array.isArray(this.selectedAudienceData)) {
            return this.selectedAudienceData.length > 0;
        }
        if (typeof this.selectedAudienceData === 'object') {
            if (Array.isArray(this.selectedAudienceData.items)) {
                return this.selectedAudienceData.items.length > 0;
            }
            return Object.keys(this.selectedAudienceData).length > 0;
        }
        return false;
    }

    get selectedAudienceLabels() {
        if (!this.targetAudience || this.targetAudience.length === 0) {
            return [];
        }
        const allOptions = this.targetAudienceOptionsData || [];
        return allOptions.filter(opt => this.targetAudience.includes(opt.value));
    }

    get questionTypeOptions() {
        return this.questionTypeOptionsData && this.questionTypeOptionsData.length
            ? this.questionTypeOptionsData
            : [
                { label: QUESTION_TYPE_LABELS.multiple, value: 'multiple' },
                { label: QUESTION_TYPE_LABELS.checkbox, value: 'checkbox' },
                { label: QUESTION_TYPE_LABELS.linear, value: 'linear' },
                { label: QUESTION_TYPE_LABELS.short, value: 'short' }
            ];
    }

    get scaleNumberOptions() {
        const options = [];
        for (let i = 1; i <= 5; i++) {
            options.push({ label: i.toString(), value: i.toString() });
        }
        return options;
    }

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

    get surveyIdForAudience() {
        return this.editSurveyId || this.savedRecordId || null;
    }

    get totalQuestions() {
        return (this.questions || []).filter(q => (q.text || '').trim() || q.type).length;
    }

    get hasSurveyTitle() {
        return this.surveyTitle && this.surveyTitle.trim();
    }

    get hasSurveyDescription() {
        return this.surveyDescription && this.surveyDescription.trim();
    }

    get hasStartDate() {
        return this.startDate && this.startDate.trim();
    }

    get hasEndDate() {
        return this.endDate && this.endDate.trim();
    }

    get formattedStartDate() {
        if (!this.startDate) return '-';
        const date = new Date(this.startDate + 'T00:00:00');
        const day = String(date.getDate()).padStart(2, '0');
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const year = date.getFullYear();
        return `${day}-${month}-${year}`;
    }

    get formattedEndDate() {
        if (!this.endDate) return '-';
        const date = new Date(this.endDate + 'T00:00:00');
        const day = String(date.getDate()).padStart(2, '0');
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const year = date.getFullYear();
        return `${day}-${month}-${year}`;
    }

    get summaryQuestions() {
        return (this.questions || [])
            .filter(q => (q.text || '').trim() && q.type)
            .map((q, index) => ({
                ...q,
                number: index + 1,
                showOptions: (q.type === 'multiple' || q.type === 'checkbox') && q.options && q.options.length > 0,
                showLinearScale: q.type === 'linear',
                showShortAnswer: q.type === 'short',
                hasLabels: q.scaleMinLabel || q.scaleMaxLabel,
                options: (q.options || []).filter(opt => (opt.text || '').trim())
            }));
    }

    get hasQuestions() {
        return this.summaryQuestions && this.summaryQuestions.length > 0;
    }

    get group1CaretClass() {
        return this.isGroup1Expanded ? 'group-caret group-caret-up' : 'group-caret group-caret-down';
    }

    get audienceSummaryItems() {
        // Ensure labels are normalized before rendering summary
        const items = this.normalizeAudienceCountsLabels(this.normalizeAudienceItems());
        const expandedMap = this.audienceSummaryExpandedMap || {};
        return items.map((item, index) => {
            const id = item.id || `aud_${index}`;
            const expanded = expandedMap[id] === undefined ? index === 0 : !!expandedMap[id];
            const criteria = Array.isArray(item.criteria) ? item.criteria : [];
            const membersLabel = (() => {
                // The numeric count is the single source of truth — a stored label string is only
                // a fallback for items that have no count (e.g. an individual's email subtitle).
                if (Number.isFinite(item.memberCount)) {
                    const count = item.memberCount;
                    return count === 1 ? '1 Member' : `${count} Members`;
                }
                if (item.membersLabel && item.membersLabel.trim()) {
                    return item.membersLabel;
                }
                return 'Audience';
            })();
            return {
                ...item,
                id,
                expanded,
                caretClass: expanded ? 'caret-icon caret-up' : 'caret-icon caret-down',
                roleTag: item.roleLabel || item.role || 'Audience',
                membersTag: membersLabel,
                criteria,
                hasCriteria: criteria.length > 0
            };
        });
    }

    handleEditStep1() {
        this.currentStep = 1;
    }

    handleEditStep2() {
        this.currentStep = 2;
    }

    handleEditStep3() {
        this.currentStep = 3;
    }

    handleToggleGroup1() {
        this.isGroup1Expanded = !this.isGroup1Expanded;
    }

    handleToggleAudienceSummary(event) {
        const id = event.currentTarget?.dataset?.id;
        if (!id) {
            return;
        }
        const next = { ...(this.audienceSummaryExpandedMap || {}) };
        next[id] = !next[id];
        this.audienceSummaryExpandedMap = next;
    }

    handleSurveyTitleChange(event) {
        let value = event.target.value;
        // Replace 2 or more consecutive spaces with a single space (allows single spaces)
        value = value.replace(/\s{2,}/g, ' ');
        
        // Update the input value if it changed
        if (event.target.value !== value) {
            event.target.value = value;
        }
        
        this.surveyTitle = value;
        if (this.titleError && value.trim()) {
            this.titleError = '';
        }
        this.persistDraft();
    }

    handleSurveyDescriptionChange(event) {
        let value = event.target.value;
        // Replace 2 or more consecutive spaces with a single space (allows single spaces)
        value = value.replace(/\s{2,}/g, ' ');
        
        // Update the textarea value if it changed
        if (event.target.value !== value) {
            event.target.value = value;
        }
        
        this.surveyDescription = value;
        this.persistDraft();
    }

    toggleDropdown(event) {
        event.stopPropagation();
        this.showAudienceDropdown = !this.showAudienceDropdown;
    }

    handleAudienceChange(event) {
        // Sync selected audience from portalAudienceSelection component
        // The portalAudienceSelection component uses a complex structure,
        // but we'll store it as-is for now and transform it when needed
        // eslint-disable-next-line no-console
        console.log('handleAudienceChange - event:', event);
        // eslint-disable-next-line no-console
        console.log('handleAudienceChange - event.detail:', event?.detail);
        
        if (event && event.detail) {
            // Handle both event.detail.selectedAudience and event.detail.audience
            const audienceData = event.detail.selectedAudience || event.detail.audience || event.detail;
            // eslint-disable-next-line no-console
            console.log('handleAudienceChange - audienceData:', audienceData);
            if (audienceData) {
                this.selectedAudienceData = audienceData;
            } else {
                this.selectedAudienceData = [];
            }
        } else if (event && Array.isArray(event)) {
            // Handle case where event itself is the array
            this.selectedAudienceData = event;
        } else {
            // Ensure selectedAudienceData is always an array
            this.selectedAudienceData = [];
        }

        // Normalize labels/counts to avoid lingering "Calculating..." placeholders
        this.selectedAudienceData = this.normalizeAudienceCountsLabels(this.selectedAudienceData);

        // eslint-disable-next-line no-console
        console.log('handleAudienceChange - final selectedAudienceData:', this.selectedAudienceData);
        this.syncAudienceSummaryExpanded();
        this.persistDraft();
    }

    toggleAudienceOption(event) {
        event.stopPropagation();
        const value = event.currentTarget.getAttribute('data-value');
        if (this.targetAudience.includes(value)) {
            this.targetAudience = this.targetAudience.filter(v => v !== value);
        } else {
            this.targetAudience = [...this.targetAudience, value];
        }
        // Force reactivity
        this.targetAudience = [...this.targetAudience];
        this.persistDraft();
    }

    removeAudience(event) {
        event.stopPropagation();
        const value = event.currentTarget.getAttribute('data-value');
        this.targetAudience = this.targetAudience.filter(v => v !== value);
        // Force reactivity
        this.targetAudience = [...this.targetAudience];
        this.persistDraft();
    }

    get showAccessGate() {
        return this.checkingAccess || this.accessDenied;
    }

    connectedCallback() {
        if (!IS_ADMIN_CONTEXT) {
            this.checkingAccess = true;
        }
        // Theme colors — portal pulls these from KenThemeConfigController. In admin
        // context the same call returns the org's defaults; failures are non-fatal.
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
            this.enforcePortalCreateAccess(color);
        }).catch(() => {
            // eslint-disable-next-line no-console
            console.log('Error getting primary color');
            this.enforcePortalCreateAccess(null);
        });

        // Close dropdown when clicking outside
        this.handleClickOutside = (event) => {
            const multiselect = this.template.querySelector('.custom-multiselect');
            if (multiselect && !multiselect.contains(event.target)) {
                this.showAudienceDropdown = false;
            }
        };
        // Use setTimeout to avoid immediate closure
        setTimeout(() => {
            document.addEventListener('click', this.handleClickOutside);
        }, 0);

        // Admin (action-override) context never reads sessionStorage drafts — those
        // belong to the portal flow where the user can navigate away mid-wizard.
        // Behavior here: New ⇒ blank wizard; Edit ⇒ server-loaded prepopulation.
        if (this.isAdminContext) {
            try {
                window.sessionStorage.removeItem(DRAFT_STORAGE_KEY);
                window.sessionStorage.removeItem(SURVEY_ID_STORAGE_KEY);
            } catch (e) {
                // sessionStorage may be locked down; ignore.
            }
            if (this._recordId) {
                this.editSurveyId = this._recordId;
                this.savedRecordId = this._recordId;
                this.loadSurveyFromServer(this._recordId);
            } else {
                this.resetAdminState();
            }
            return;
        }

        // Portal context — keep the draft-persistence flow so users can resume work.
        if (this._recordId) {
            this.editSurveyId = this._recordId;
            this.savedRecordId = this._recordId;
            this.loadSurveyFromServer(this._recordId);
        } else {
            this.loadDraft();
        }
    }

    /**
     * Fetches an existing survey + its questions from Apex and seeds the wizard.
     * Used by the admin Edit action override (and any other host that passes @api recordId).
     */
    async loadSurveyFromServer(surveyId) {
        if (!surveyId || this._hydratedRecordId === surveyId) {
            return;
        }
        try {
            const resp = await getSurveyForEdit({ surveyId });
            const dto = resp && resp.data ? resp.data : null;
            if (!dto) {
                return;
            }
            this._hydratedRecordId = surveyId;
            this.surveyTitle = dto.title || '';
            this.surveyDescription = dto.description || '';
            this.targetAudience = Array.isArray(dto.targetAudience) ? dto.targetAudience : [];
            this.startDate = dto.startDate || '';
            this.endDate = dto.endDate || '';
            this.questions = (dto.questions || []).map((q, idx) => {
                const type = q.type || 'short';
                const options = (q.options || []).map((opt, oIdx) => ({
                    id: `${Date.now()}_${idx}_${oIdx}`,
                    text: opt.text || '',
                    letter: String.fromCharCode(97 + oIdx)
                }));
                return {
                    id: `${Date.now()}_${idx}`,
                    number: idx + 1,
                    text: q.text || '',
                    type,
                    required: !!q.required,
                    options,
                    scaleMin: q.scaleMin != null ? String(q.scaleMin) : '1',
                    scaleMax: q.scaleMax != null ? String(q.scaleMax) : '5',
                    scaleMinLabel: q.scaleMinLabel || '',
                    scaleMaxLabel: q.scaleMaxLabel || '',
                    showMultipleOptions: type === 'multiple' || type === 'checkbox',
                    isMultiple: type === 'multiple',
                    isCheckboxType: type === 'checkbox',
                    showLinearScale: type === 'linear',
                    showShortAnswer: type === 'short',
                    nextOptionNumber: options.length + 1,
                    hasInsufficientOptions: (type === 'multiple' || type === 'checkbox') && options.length < 2,
                    cannotDeleteOption: (type === 'multiple' || type === 'checkbox') && options.length <= 2
                };
            });
            if (!this.questions.length) {
                // Keep the wizard usable even when a survey was saved as a draft with no questions.
                this.questions = this.defaultEmptyQuestions();
            }
            this.isStep1Completed = true;
            this.isStep2Completed = true;
            this.persistDraft();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('loadSurveyFromServer error', e);
            const message = e?.body?.message || e?.message || 'Unable to load survey.';
            this.showError('Error', message);
        }
    }

    resetAdminState() {
        this.editSurveyId = null;
        this.savedRecordId = null;
        this._hydratedRecordId = null;
        this.surveyTitle = '';
        this.surveyDescription = '';
        this.targetAudience = [];
        this.selectedAudienceData = [];
        this.startDate = '';
        this.endDate = '';
        this.titleError = '';
        this.startDateError = '';
        this.endDateError = '';
        this.questions = this.defaultEmptyQuestions();
        this.enableAnonymous = false;
        this.currentStep = 1;
        this.isStep1Completed = false;
        this.isStep2Completed = false;
        this.isStep3Completed = false;
        this.isStep4Completed = false;
        this.audienceSummaryExpandedMap = {};
    }

    defaultEmptyQuestions() {
        return [{
            id: '1', number: 1, text: '', type: '', required: false, options: [],
            scaleMin: '1', scaleMax: '5', scaleMinLabel: '', scaleMaxLabel: '',
            showMultipleOptions: false, isMultiple: false, isCheckboxType: false,
            showLinearScale: false, showShortAnswer: false,
            nextOptionNumber: 1, hasInsufficientOptions: false, cannotDeleteOption: false
        }];
    }

    // Portal URL guard: if "Allow Create Survey" is off, a portal user reaching
    // /create-survey directly is bounced back to the Surveys page. Admin/internal
    // context is never gated.
    enforcePortalCreateAccess(config) {
        this.checkingAccess = false;
        if (IS_ADMIN_CONTEXT) {
            return;
        }
        if (config && config.createSurvey !== false) {
            return;
        }
        this.accessDenied = true;
        const base = (basePath || '').replace(/\/+$/, '');
        window.location.assign(`${base}/survey`);
    }

    renderedCallback() {
        // Inject dropdown styles
        this.injectDropdownStyles();
    }

    disconnectedCallback() {
        if (this.handleClickOutside) {
            document.removeEventListener('click', this.handleClickOutside);
        }
        if (this.savedAudienceSearchTimer) {
            clearTimeout(this.savedAudienceSearchTimer);
        }
        // Clean up injected styles
        if (this.styleElement && this.styleElement.parentNode) {
            this.styleElement.parentNode.removeChild(this.styleElement);
        }
        window.clearTimeout(this.successTimeout);
        window.clearTimeout(this.errorTimeout);
        this.clearRedirectTimer();
    }

    injectDropdownStyles() {
        if (!this.styleElement) {
            this.styleElement = document.createElement('style');
            this.styleElement.setAttribute('data-component', 'create-survey-dropdown-styles');
            document.head.appendChild(this.styleElement);
            
            this.styleElement.textContent = `
                .slds-listbox,
                .slds-dropdown {
                    background-color: #ffffff !important;
                }
                .slds-listbox__option,
                .slds-dropdown__item {
                    background-color: #ffffff !important;
                    border: none !important;
                    border-top: none !important;
                    border-bottom: none !important;
                    border-left: none !important;
                    border-right: none !important;
                    box-shadow: none !important;
                }
                .slds-listbox__option:hover,
                .slds-dropdown__item:hover {
                    background-color: #f3f4f6 !important;
                    border: none !important;
                    border-top: none !important;
                    border-bottom: none !important;
                    border-left: none !important;
                    border-right: none !important;
                    outline: none !important;
                    box-shadow: none !important;
                }
                .slds-listbox__option[aria-selected="true"],
                .slds-dropdown__item[aria-selected="true"] {
                    background-color: #ffffff !important;
                    border: none !important;
                    border-top: none !important;
                    border-bottom: none !important;
                    border-left: none !important;
                    border-right: none !important;
                    box-shadow: none !important;
                }
                .slds-listbox__option *,
                .slds-dropdown__item *,
                .slds-listbox__option:hover *,
                .slds-dropdown__item:hover * {
                    border: none !important;
                    border-top: none !important;
                    border-bottom: none !important;
                    border-left: none !important;
                    border-right: none !important;
                    box-shadow: none !important;
                }
            `;
        }
    }

    handleAnonymousToggle(event) {
        this.enableAnonymous = event.target.checked;
        this.persistDraft();
    }

    async handleNextStep() {
        // Validate current step before proceeding
        if (this.currentStep === 1) {
            let hasError = false;
            if (!this.surveyTitle || !this.surveyTitle.trim()) {
                this.titleError = 'Survey title is required.';
                hasError = true;
            }
            if (!this.startDate) {
                this.startDateError = 'Start date is required.';
                hasError = true;
            } else if (this.startDateError) {
                hasError = true;
            }
            if (!this.endDate) {
                this.endDateError = 'End date is required.';
                hasError = true;
            } else if (this.endDateError) {
                hasError = true;
            }
            if (hasError) return;
            const saved = await this.saveDraftSurvey();
            if (!saved) {
                return;
            }
            this.isStep1Completed = true;
        } else if (this.currentStep === 2) {
            // Require at least one selected audience to proceed
            if (!this.hasSelectedAudience) {
                this.showError('Error', 'Please select at least one target audience.');
                return;
            }
            // The audience must be SAVED as a segmentation and LINKED to the survey
            // before advancing. Edited-after-save selections re-save automatically;
            // a never-saved selection blocks and opens the save dialog.
            const audienceWrapper = this.template.querySelector('c-ken-target-audience');
            let audienceLinked = false;
            if (audienceWrapper) {
                try {
                    if (typeof audienceWrapper.persistCurrentSelection === 'function') {
                        await audienceWrapper.persistCurrentSelection();
                    }
                    if (typeof audienceWrapper.ensureSegmentationLink === 'function') {
                        audienceLinked = await audienceWrapper.ensureSegmentationLink();
                    }
                } catch (e) {
                    // eslint-disable-next-line no-console
                    console.warn('Audience persistence/link failed', e);
                    audienceLinked = false;
                }
            }
            if (!audienceLinked && !(audienceWrapper && audienceWrapper.hasUnsavedChanges)) {
                audienceLinked = await this.isAudienceLinkedOnServer(audienceWrapper);
            }
            if (!audienceLinked) {
                this.showError('Error', 'Please save your target audience to continue.');
                if (audienceWrapper && typeof audienceWrapper.openSaveDialog === 'function') {
                    audienceWrapper.openSaveDialog();
                }
                return;
            }
            this.isStep2Completed = true;
        } else if (this.currentStep === 3) {
            const questions = (this.questions || []).filter(q => (q.text || '').trim() || q.type);
            if (!questions.length) {
                this.showError('Error', 'Add at least one question.');
                return;
            }
            const hasInvalidQuestion = questions.some(q => !(q.text || '').trim() || !q.type);
            if (hasInvalidQuestion) {
                this.showError('Error', 'Each question needs a prompt and type.');
                return;
            }
            const hasMissingOptions = questions.some(q =>
                (q.type === 'multiple' || q.type === 'checkbox') &&
                (!q.options || !q.options.length || q.options.some(opt => !(opt.text || '').trim()))
            );
            if (hasMissingOptions) {
                this.showError('Error', 'Multiple/Checkbox questions need option text.');
                return;
            }
            const hasInsufficientOptions = questions.some(q =>
                (q.type === 'multiple' || q.type === 'checkbox') &&
                (!q.options || q.options.length < 2)
            );
            if (hasInsufficientOptions) {
                this.showError('Error', 'Single Select and Checkbox questions must have at least 2 options.');
                return;
            }
            this.isStep3Completed = true;
        }

        if (this.currentStep < 4) {
            this.currentStep++;
        }
    }

    /**
     * Server-truth fallback for the step-2 audience gate, consulted only when the
     * selection has NO unsaved edits (a dirty selection must save or block). The
     * wrapper/builder can report false from stale client state (or throw) even after
     * a successful save, so before blocking we accept the step when the survey already
     * has a linked segmentation — or the audience is saved and the survey record does
     * not exist yet.
     */
    async isAudienceLinkedOnServer(audienceWrapper) {
        const savedSegId = audienceWrapper ? audienceWrapper.segmentationId : null;
        const parentId = this.surveyIdForAudience;
        if (!parentId) {
            return !!savedSegId;
        }
        try {
            const linked = await getLinkedSegmentation({ parentObjectType: 'Survey', parentId });
            return !!linked;
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Linked-audience fallback check failed', e);
            return false;
        }
    }

    handlePreviousStep() {
        if (this.currentStep > 1) {
            this.currentStep--;
        }
    }

    handleCancel() {
        this.handleDiscard();
    }

    handleStartDateChange(event) {
        const selectedDate = event.target.value;
        const today = new Date().toISOString().split('T')[0]; // Get today's date in YYYY-MM-DD format
        
        // Validate start date - must be today or future date
        if (selectedDate && selectedDate < today) {
            this.startDateError = 'Start date cannot be in the past. Please select today or a future date.';
            this.startDate = ''; // Clear the invalid date
            this.persistDraft();
            return;
        }
        
        this.startDateError = '';
        this.startDate = selectedDate;
        
        // If end date exists and is before the new start date, clear it
        if (this.endDate && this.endDate < selectedDate) {
            this.endDate = '';
            this.endDateError = '';
        }
        
        // Revalidate end date if it exists
        if (this.endDate) {
            this.validateEndDate(this.endDate);
        }
        
        this.persistDraft();
    }

    handleEndDateChange(event) {
        const selectedDate = event.target.value;
        this.endDate = selectedDate;
        this.validateEndDate(selectedDate);
        this.persistDraft();
    }

    validateEndDate(selectedDate) {
        if (!selectedDate) {
            this.endDateError = '';
            return;
        }
        
        if (!this.startDate) {
            this.endDateError = 'Please select a start date first.';
            return;
        }
        
        // End date must be equal to or after start date
        if (selectedDate < this.startDate) {
            this.endDateError = 'End date must be equal to or after the start date.';
            return;
        }
        
        this.endDateError = '';
    }

    get todayDate() {
        return new Date().toISOString().split('T')[0]; // Returns YYYY-MM-DD format
    }

    get minEndDate() {
        return this.startDate || this.todayDate;
    }

    handleQuestionChange(event) {
        const questionId = event.currentTarget.getAttribute('data-question-id');
        const value = event.target.value;
        
        this.questions = this.questions.map(q => {
            if (q.id === questionId) {
                return { ...q, text: value };
            }
            return q;
        });
        this.persistDraft();
    }

    handleQuestionTypeChange(event) {
        const questionId = event.currentTarget.getAttribute('data-question-id');
        const value = event.detail.value;
        
        this.questions = this.questions.map(q => {
            if (q.id === questionId) {
                // Initialize options for multiple choice and checkbox types
                let updatedQuestion = { ...q, type: value };
                if ((value === 'multiple' || value === 'checkbox') && (!q.options || q.options.length === 0)) {
                    // Start with empty options (placeholder "Add option") so the
                    // author must type real choices — validateSurvey already
                    // requires >=2 non-empty options — instead of shipping the
                    // literal "Option 1"/"Option 2" placeholders.
                    updatedQuestion.options = [
                        { id: Date.now().toString(), text: '', letter: 'a' },
                        { id: (Date.now() + 1).toString(), text: '', letter: 'b' }
                    ];
                }
                // Set display flags
                updatedQuestion.showMultipleOptions = value === 'multiple' || value === 'checkbox';
                updatedQuestion.isMultiple = value === 'multiple';
                updatedQuestion.isCheckboxType = value === 'checkbox';
                updatedQuestion.showLinearScale = value === 'linear';
                updatedQuestion.showShortAnswer = value === 'short';
                // Initialize linear scale defaults when type is set to linear
                if (value === 'linear') {
                    // Set as strings to match combobox value format
                    updatedQuestion.scaleMin = updatedQuestion.scaleMin ? updatedQuestion.scaleMin.toString() : '1';
                    updatedQuestion.scaleMax = updatedQuestion.scaleMax ? updatedQuestion.scaleMax.toString() : '5';
                }
                // Update next option number
                updatedQuestion.nextOptionNumber = updatedQuestion.options ? updatedQuestion.options.length + 1 : 1;
                // Check for insufficient options
                updatedQuestion.hasInsufficientOptions = (value === 'multiple' || value === 'checkbox') && 
                                                         (!updatedQuestion.options || updatedQuestion.options.length < 2);
                // Check if option can be deleted (must have more than 2 options)
                updatedQuestion.cannotDeleteOption = (value === 'multiple' || value === 'checkbox') && 
                                                      (!updatedQuestion.options || updatedQuestion.options.length <= 2);
                return updatedQuestion;
            }
            return q;
        });
        this.persistDraft();
    }

    handleAddOption(event) {
        const questionId = event.currentTarget.getAttribute('data-question-id');
        const question = this.questions.find(q => q.id === questionId);
        if (question && question.options) {
            const newOptionNumber = question.options.length + 1;
            const letter = String.fromCharCode(96 + newOptionNumber);
            const newOption = {
                id: Date.now().toString(),
                text: `Option ${newOptionNumber}`,
                letter: letter
            };
            this.questions = this.questions.map(q => {
                if (q.id === questionId) {
                    const updatedOptions = [...q.options, newOption];
                    const updatedQuestion = { 
                        ...q, 
                        options: updatedOptions,
                        nextOptionNumber: updatedOptions.length + 1
                    };
                    // Update insufficient options flag
                    updatedQuestion.hasInsufficientOptions = (q.type === 'multiple' || q.type === 'checkbox') && 
                                                              updatedOptions.length < 2;
                    // Update cannot delete option flag
                    updatedQuestion.cannotDeleteOption = (q.type === 'multiple' || q.type === 'checkbox') && 
                                                         updatedOptions.length <= 2;
                    return updatedQuestion;
                }
                return q;
            });
            this.persistDraft();
        }
    }

    handleRequiredToggle(event) {
        const questionId = event.currentTarget.getAttribute('data-question-id');
        const checked = event.target.checked;
        
        this.questions = this.questions.map(q => {
            if (q.id === questionId) {
                return { ...q, required: checked };
            }
            return q;
        });
        this.persistDraft();
    }

    handleAddQuestion() {
        const newQuestionNumber = this.questions.length + 1;
        const newQuestion = {
            id: Date.now().toString(),
            number: newQuestionNumber,
            text: '',
            type: '',
            required: false,
            options: [],
            scaleMin: '1',
            scaleMax: '5',
            scaleMinLabel: '',
            scaleMaxLabel: '',
            showMultipleOptions: false,
            isMultiple: false,
            isCheckboxType: false,
            showLinearScale: false,
            showShortAnswer: false,
            nextOptionNumber: 1,
            hasInsufficientOptions: false,
            cannotDeleteOption: false
        };
        this.questions = [...this.questions, newQuestion];
        this.persistDraft();
    }


    handleOptionChange(event) {
        const questionId = event.currentTarget.getAttribute('data-question-id');
        const optionId = event.currentTarget.getAttribute('data-option-id');
        const value = event.target.value;
        
        this.questions = this.questions.map(q => {
            if (q.id === questionId && q.options) {
                const updatedQuestion = {
                    ...q,
                    options: q.options.map(opt => {
                        if (opt.id === optionId) {
                            return { ...opt, text: value };
                        }
                        return opt;
                    })
                };
                // Update insufficient options flag
                updatedQuestion.hasInsufficientOptions = (q.type === 'multiple' || q.type === 'checkbox') && 
                                                          (!updatedQuestion.options || updatedQuestion.options.length < 2);
                // Update cannot delete option flag
                updatedQuestion.cannotDeleteOption = (q.type === 'multiple' || q.type === 'checkbox') && 
                                                      (!updatedQuestion.options || updatedQuestion.options.length <= 2);
                return updatedQuestion;
            }
            return q;
        });
        this.persistDraft();
    }

    handleDeleteOption(event) {
        const questionId = event.currentTarget.getAttribute('data-question-id');
        const optionId = event.currentTarget.getAttribute('data-option-id');
        const question = this.questions.find(q => q.id === questionId);
        
        // Prevent deletion if it would leave less than 2 options
        if (question && question.options && question.options.length <= 2) {
            this.showError('Cannot delete option', 'Single Select and Checkbox questions must have at least 2 options.');
            return;
        }
        
        this.questions = this.questions.map(q => {
            if (q.id === questionId && q.options) {
                const updatedOptions = q.options.filter(opt => opt.id !== optionId);
                // Reassign letters to remaining options
                const optionsWithLetters = updatedOptions.map((opt, idx) => ({
                    ...opt,
                    letter: String.fromCharCode(97 + idx)
                }));
                const updatedQuestion = {
                    ...q,
                    options: optionsWithLetters,
                    nextOptionNumber: optionsWithLetters.length + 1
                };
                // Update insufficient options flag
                updatedQuestion.hasInsufficientOptions = (q.type === 'multiple' || q.type === 'checkbox') && 
                                                          optionsWithLetters.length < 2;
                // Update cannot delete option flag
                updatedQuestion.cannotDeleteOption = (q.type === 'multiple' || q.type === 'checkbox') && 
                                                      optionsWithLetters.length <= 2;
                return updatedQuestion;
            }
            return q;
        });
        this.persistDraft();
    }

    handleScaleMinChange(event) {
        const questionId = event.currentTarget.getAttribute('data-question-id');
        const value = event.detail.value;
        
        this.questions = this.questions.map(q => {
            if (q.id === questionId) {
                // Store as string to match combobox value format
                return { ...q, scaleMin: value || '1' };
            }
            return q;
        });
        this.persistDraft();
    }

    handleScaleMaxChange(event) {
        const questionId = event.currentTarget.getAttribute('data-question-id');
        const value = event.detail.value;
        
        this.questions = this.questions.map(q => {
            if (q.id === questionId) {
                // Store as string to match combobox value format
                return { ...q, scaleMax: value || '5' };
            }
            return q;
        });
        this.persistDraft();
    }

    handleScaleMinLabelChange(event) {
        const questionId = event.currentTarget.getAttribute('data-question-id');
        const value = event.target.value;
        
        this.questions = this.questions.map(q => {
            if (q.id === questionId) {
                return { ...q, scaleMinLabel: value };
            }
            return q;
        });
        this.persistDraft();
    }

    handleScaleMaxLabelChange(event) {
        const questionId = event.currentTarget.getAttribute('data-question-id');
        const value = event.target.value;
        
        this.questions = this.questions.map(q => {
            if (q.id === questionId) {
                return { ...q, scaleMaxLabel: value };
            }
            return q;
        });
        this.persistDraft();
    }

    handleDeleteQuestion(event) {
        const questionId = event.currentTarget.getAttribute('data-question-id');
        this.questions = this.questions.filter(q => q.id !== questionId);
        
        // Renumber questions
        this.questions = this.questions.map((q, index) => ({
            ...q,
            number: index + 1
        }));
        this.persistDraft();
    }

    draggedQuestionId = null;

    handleDragStart(event) {
        this.draggedQuestionId = event.currentTarget.getAttribute('data-question-id');
        event.dataTransfer.effectAllowed = 'move';
        event.currentTarget.style.opacity = '0.5';
    }

    handleDragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        const targetCard = event.currentTarget;
        const targetQuestionId = targetCard.getAttribute('data-question-id');
        
        if (targetQuestionId && targetQuestionId !== this.draggedQuestionId) {
            targetCard.classList.add('drag-over');
        }
    }

    handleDrop(event) {
        event.preventDefault();
        const targetQuestionId = event.currentTarget.getAttribute('data-question-id');
        const draggedQuestionId = this.draggedQuestionId;
        
        if (targetQuestionId && draggedQuestionId && targetQuestionId !== draggedQuestionId) {
            const draggedIndex = this.questions.findIndex(q => q.id === draggedQuestionId);
            const targetIndex = this.questions.findIndex(q => q.id === targetQuestionId);
            
            if (draggedIndex !== -1 && targetIndex !== -1) {
                const newQuestions = [...this.questions];
                const [draggedQuestion] = newQuestions.splice(draggedIndex, 1);
                newQuestions.splice(targetIndex, 0, draggedQuestion);
                
                // Renumber questions
                newQuestions.forEach((q, index) => {
                    q.number = index + 1;
                });
                
                this.questions = newQuestions;
                this.persistDraft();
            }
        }
        
        event.currentTarget.classList.remove('drag-over');
    }

    handleDragEnd(event) {
        event.currentTarget.style.opacity = '1';
        const allCards = this.template.querySelectorAll('.question-card');
        allCards.forEach(card => card.classList.remove('drag-over'));
        this.draggedQuestionId = null;
    }

    handleDiscard() {
        // Save editSurveyId before clearing draft
        const wasEditing = !!this.editSurveyId;
        this.clearDraft();
        // Pass the edit state to navigation
        this.navigateToSurveyHome(wasEditing);
    }

    async saveDraftSurvey() {
        const payload = {
            title: this.surveyTitle,
            description: this.surveyDescription,
            targetAudience: this.targetAudience,
            startDate: this.startDate,
            endDate: this.endDate,
            questions: []
        };

        try {
            const surveyId = await saveSurveyDraft({
                request: payload,
                surveyId: this.editSurveyId
            });
            this.setSurveyId(surveyId);
            return true;
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('saveDraftSurvey error', JSON.stringify(error));
            const message = error?.body?.message || error?.message || 'Unable to save survey.';
            this.showError('Error', message);
            return false;
        }
    }

    async handleSave() {
        const validationError = this.validateSurvey();
        if (validationError) {
            this.showError('Error', validationError);
            return;
        }

        // eslint-disable-next-line no-console
        console.log('createSurvey state before save', {
            surveyTitle: this.surveyTitle,
            surveyDescription: this.surveyDescription,
            targetAudience: this.targetAudience,
            startDate: this.startDate,
            endDate: this.endDate,
            questionsCount: this.questions ? this.questions.length : 0
        });

        const filteredQuestions = (this.questions || [])
            .filter(q => (q.text || '').trim() || q.type)
            .map(q => ({
                text: (q.text || '').trim(),
                type: q.type,
                required: q.required,
                options: (q.options || [])
                    .filter(opt => (opt.text || '').trim())
                    .map(opt => ({ text: opt.text.trim() })),
                scaleMin: parseInt(q.scaleMin) || 1,
                scaleMax: parseInt(q.scaleMax) || 5,
                scaleMinLabel: (q.scaleMinLabel || '').trim(),
                scaleMaxLabel: (q.scaleMaxLabel || '').trim()
            }));

        const payload = {
            title: this.surveyTitle,
            description: this.surveyDescription,
            targetAudience: this.targetAudience,
            startDate: this.startDate,
            endDate: this.endDate,
            enableAnonymous: this.enableAnonymous,
            questions: filteredQuestions
        };
        // eslint-disable-next-line no-console
        console.log('createSurvey payload', JSON.stringify(payload));

        try {
            const surveyId = this.editSurveyId
                ? await updateSurveyWithQuestions({ request: payload, surveyId: this.editSurveyId })
                : await createSurveyWithQuestions({ request: payload });
            // eslint-disable-next-line no-console
            console.log('createSurvey save result surveyId', surveyId);
            this.savedRecordId = surveyId;
            this.showSuccess('Success', 'Survey created successfully.');
            this.clearDraft();
            // In admin context, immediately wipe all tracked properties so that if
            // Lightning reuses this component instance for the next "New" action the
            // wizard always opens blank. The redirect spinner covers the reset.
            if (this.isAdminContext) {
                this.resetAdminState();
            }
            this.scheduleRedirect(surveyId);
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('createSurvey save error', JSON.stringify(error));
            const message = error?.body?.message || error?.message || 'Unable to save survey.';
            this.showError('Error', message);
        }
    }

    validateSurvey() {
        if (!this.surveyTitle || !this.surveyTitle.trim()) {
            return 'Survey title is required.';
        }
        if (!this.startDate) {
            return 'Start date is required.';
        }
        if (this.startDateError) {
            return this.startDateError;
        }
        if (!this.endDate) {
            return 'End date is required.';
        }
        if (this.endDateError) {
            return this.endDateError;
        }
      //  if (!this.hasSelectedAudience) {
       //     return 'Please select at least one target audience.';
      //  }
        const questions = (this.questions || []).filter(q => (q.text || '').trim() || q.type);
        if (!questions.length) {
            return 'Add at least one question.';
        }
        const hasInvalidQuestion = questions.some(q => !(q.text || '').trim() || !q.type);
        if (hasInvalidQuestion) {
            return 'Each question needs a prompt and type.';
        }
        const hasMissingOptions = questions.some(q =>
            (q.type === 'multiple' || q.type === 'checkbox') &&
            (!q.options || !q.options.length || q.options.some(opt => !(opt.text || '').trim()))
        );
        if (hasMissingOptions) {
            return 'Multiple/Checkbox questions need option text.';
        }
        const hasInsufficientOptions = questions.some(q =>
            (q.type === 'multiple' || q.type === 'checkbox') &&
            (!q.options || q.options.length < 2)
        );
        if (hasInsufficientOptions) {
            return 'Single Select and Checkbox questions must have at least 2 options.';
        }
        return '';
    }

    normalizeQuestionTypeValue(value) {
        const lower = (value || '').toLowerCase();
        if (lower.includes('multiple')) {
            return 'multiple';
        }
        if (lower.includes('checkbox')) {
            return 'checkbox';
        }
        if (lower.includes('linear') || lower.includes('rating')) {
            return 'linear';
        }
        if (lower.includes('short') || lower.includes('comment') || lower.includes('file') || lower.includes('dropdown')) {
            // Map any remaining text-like options to short so UI can render a text answer
            return 'short';
        }
        return 'short';
    }

    buildQuestionTypeOptions(values) {
        if (!Array.isArray(values)) {
            return [];
        }
        // Keep only allowed types and order them explicitly
        const normalizedToLabel = {};
        values.forEach(val => {
            const normalized = this.normalizeQuestionTypeValue(val.value);
            if (ALLOWED_QUESTION_TYPES.includes(normalized) && !normalizedToLabel[normalized]) {
                normalizedToLabel[normalized] = QUESTION_TYPE_LABELS[normalized] || val.label;
            }
        });

        // Ensure all allowed options are present even if picklist is missing them
        ALLOWED_QUESTION_TYPES.forEach(t => {
            if (!normalizedToLabel[t]) {
                normalizedToLabel[t] = QUESTION_TYPE_LABELS[t];
            }
        });

        return ALLOWED_QUESTION_TYPES.map(t => ({
            label: normalizedToLabel[t],
            value: t
        }));
    }

    persistDraft() {
        // Admin wizard is single-session — no sessionStorage breadcrumbs.
        if (this.isAdminContext) {
            return;
        }
        const draft = {
            existingSurveyId: this.editSurveyId,
            surveyTitle: this.surveyTitle,
            surveyDescription: this.surveyDescription,
            targetAudience: this.targetAudience,
            selectedAudienceData: this.selectedAudienceData,
            startDate: this.startDate,
            endDate: this.endDate,
            questions: this.questions,
            enableAnonymous: this.enableAnonymous,
            currentStep: this.currentStep,
            isStep1Completed: this.isStep1Completed,
            isStep2Completed: this.isStep2Completed,
            isStep3Completed: this.isStep3Completed,
            isStep4Completed: this.isStep4Completed,
            audienceSummaryExpandedMap: this.audienceSummaryExpandedMap
        };
        try {
            window.sessionStorage.setItem(DRAFT_STORAGE_KEY, JSON.stringify(draft));
            if (this.editSurveyId) {
                window.sessionStorage.setItem(SURVEY_ID_STORAGE_KEY, this.editSurveyId);
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Unable to persist draft', e);
        }
    }

    clearDraft() {
        try {
            this.editSurveyId = null;
            window.sessionStorage.removeItem(DRAFT_STORAGE_KEY);
            window.sessionStorage.removeItem(SURVEY_ID_STORAGE_KEY);
            if (window.localStorage) {
                window.localStorage.removeItem(DRAFT_STORAGE_KEY);
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Unable to clear draft', e);
        }
    }

    loadDraft() {
        try {
            const stored = window.sessionStorage.getItem(DRAFT_STORAGE_KEY);
            const storedSurveyId = window.sessionStorage.getItem(SURVEY_ID_STORAGE_KEY);
            if (!stored && !storedSurveyId) {
                return;
            }
            const draft = stored ? JSON.parse(stored) : {};
            this.editSurveyId = draft.existingSurveyId || storedSurveyId || null;
            if (this.editSurveyId) {
                this.savedRecordId = this.editSurveyId;
            }
            this.surveyTitle = draft.surveyTitle || '';
            this.surveyDescription = draft.surveyDescription || '';
            this.targetAudience = draft.targetAudience || [];
            this.selectedAudienceData = this.normalizeAudienceCountsLabels(draft.selectedAudienceData || []);
            this.startDate = draft.startDate || '';
            this.endDate = draft.endDate || '';
            this.questions = draft.questions || this.questions;
            this.enableAnonymous = draft.enableAnonymous || false;
            this.currentStep = draft.currentStep || 1;
            this.isStep1Completed = draft.isStep1Completed || false;
            this.isStep2Completed = draft.isStep2Completed || false;
            this.isStep3Completed = draft.isStep3Completed || false;
            this.isStep4Completed = draft.isStep4Completed || false;
            this.audienceSummaryExpandedMap = draft.audienceSummaryExpandedMap || {};
            this.syncAudienceSummaryExpanded();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Unable to load draft', e);
        }
    }

    setSurveyId(surveyId) {
        if (!surveyId) {
            return;
        }
        this.editSurveyId = surveyId;
        this.savedRecordId = surveyId;
        if (!this.isAdminContext) {
            try {
                window.sessionStorage.setItem(SURVEY_ID_STORAGE_KEY, surveyId);
            } catch (e) {
                // eslint-disable-next-line no-console
                console.error('Unable to store survey id', e);
            }
        }
        this.persistDraft();
    }

    normalizeAudienceItems() {
        if (Array.isArray(this.selectedAudienceData)) {
            return this.selectedAudienceData;
        }
        if (this.selectedAudienceData && Array.isArray(this.selectedAudienceData.items)) {
            return this.selectedAudienceData.items;
        }
        if (this.selectedAudienceData && typeof this.selectedAudienceData === 'object') {
            return Object.values(this.selectedAudienceData).filter((item) => !!item);
        }
        return [];
    }

    // Ensure membersLabel is consistent and static (no lingering "Calculating...")
    normalizeAudienceCountsLabels(items) {
        const list = Array.isArray(items) ? items : [];
        return list.map((it) => {
            const item = { ...it };
            let count = null;
            
            // Handle case where memberCount is a number
            if (Number.isFinite(item.memberCount)) {
                count = item.memberCount;
            } 
            // Handle case where memberCount is a string representation of a number
            else if (typeof item.memberCount === 'string' && item.memberCount.trim() !== '') {
                const parsed = Number(item.memberCount.trim());
                if (Number.isFinite(parsed)) {
                    count = parsed;
                }
            }
            
            // If count exists, derive a stable label
            if (count !== null) {
                item.membersLabel = count === 1 ? '1 Member' : `${count} Members`;
                item.memberCount = count; // Ensure memberCount is properly set
                return item;
            }

            // If we have a memberCount but it's not finite (like NaN), try to parse it
            if (item.memberCount !== undefined && item.memberCount !== null && item.memberCount !== '') {
                const parsedCount = Number(item.memberCount);
                if (Number.isFinite(parsedCount)) {
                    item.membersLabel = parsedCount === 1 ? '1 Member' : `${parsedCount} Members`;
                    item.memberCount = parsedCount;
                    return item;
                }
            }

            // If label is explicitly "Calculating..." but we have no count, replace with a neutral fallback
            if (typeof item.membersLabel === 'string' && item.membersLabel.toLowerCase().includes('calculating')) {
                // Prefer any existing label hints; otherwise fallback to generic 'Audience'
                item.membersLabel = item.roleLabel ? `${item.roleLabel}` : (item.role ? `${item.role}` : 'Audience');
            }
            
            // If membersLabel is still not set properly, fallback to a reasonable default
            if (!item.membersLabel) {
                item.membersLabel = 'Audience';
            }
            
            // If membersLabel is set to 'Alumni' (which shouldn't happen but might due to data issues), 
            // replace with a proper default
            if (item.membersLabel === 'Alumni') {
                item.membersLabel = 'Audience';
            }
            
            // Handle case where we have a numeric count in a different field or format
            if (item.memberCount === 0 && !item.membersLabel) {
                item.membersLabel = '0 Members';
            }
            
            return item;
        });
    }

    syncAudienceSummaryExpanded() {
        const items = this.normalizeAudienceItems();
        const next = { ...(this.audienceSummaryExpandedMap || {}) };
        items.forEach((item, index) => {
            const id = item.id || `aud_${index}`;
            if (next[id] === undefined) {
                next[id] = index === 0;
            }
        });
        this.audienceSummaryExpandedMap = next;
    }

    showSuccess(title, message) {
        this.successTitle = title;
        this.successDescription = message;
        this.isSuccessToastVisible = true;
        this.isErrorToastVisible = false;
        this.clearRedirectTimer();
        this.showSuccessLoader = false;
        window.clearTimeout(this.successTimeout);
        this.successTimeout = window.setTimeout(() => {
            this.isSuccessToastVisible = false;
        }, 1500);
    }

    showError(title, message) {
        this.errorTitle = title;
        this.errorDescription = message;
        this.isErrorToastVisible = true;
        this.isSuccessToastVisible = false;
        this.clearRedirectTimer();
        this.showSuccessLoader = false;
        window.clearTimeout(this.errorTimeout);
        this.errorTimeout = window.setTimeout(() => {
            this.isErrorToastVisible = false;
        }, 1500);
    }

    closeSuccessModal() {
        this.isSuccessToastVisible = false;
    }

    closeErrorModal() {
        this.isErrorToastVisible = false;
    }

    scheduleRedirect(recordId) {
        this.clearRedirectTimer();
        if (!recordId) {
            return;
        }
        this.showSuccessLoader = true;
        this.redirectTimeout = window.setTimeout(() => {
            this.showSuccessLoader = false;
            this.navigateToSurvey(recordId);
        }, 1500);
    }

    clearRedirectTimer() {
        if (this.redirectTimeout) {
            window.clearTimeout(this.redirectTimeout);
            this.redirectTimeout = null;
        }
    }

    navigateToSurvey(recordId) {
        // Admin (backend) context — drop to the standard Ken_Survey__c record page.
        if (this.isAdminContext) {
            if (recordId) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId,
                        objectApiName: 'Ken_Survey__c',
                        actionName: 'view'
                    }
                });
            }
            return;
        }
        // Portal/Experience context: the internal record page doesn't exist here and the
        // survey__c page with a recordId lands on an error page, so route to the community
        // Surveys list page (mirrors how event creation routes to the Hosted Events page).
        try {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: {
                    name: 'all_surveys__c'
                }
            }, true);
        } catch (e) {
            window.location.assign(`${basePath}/all-surveys`);
        }
    }

    navigateToSurveyHome(wasEditing = false) {
        // Admin context — cancel / discard should land on the object list view, or
        // the record page when we were editing an existing survey.
        if (this.isAdminContext) {
            if (wasEditing && this.editSurveyId) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: this.editSurveyId,
                        objectApiName: 'Ken_Survey__c',
                        actionName: 'view'
                    }
                });
            } else {
                this[NavigationMixin.Navigate]({
                    type: 'standard__objectPage',
                    attributes: {
                        objectApiName: 'Ken_Survey__c',
                        actionName: 'home'
                    }
                });
            }
            return;
        }
        try {
            // If editing a survey, navigate to surveys list page (Your Surveys section)
            if (wasEditing || this.editSurveyId) {
                this[NavigationMixin.Navigate]({
                    type: 'comm__namedPage',
                    attributes: {
                        name: 'all_surveys__c'
                    }
                });
            } else {
                // If creating a new survey, navigate to surveys home page
                this[NavigationMixin.Navigate]({
                    type: 'comm__namedPage',
                    attributes: {
                        name: 'survey__c'
                    }
                });
            }
        } catch (e) {
            // Fallback navigation
            if (wasEditing || this.editSurveyId) {
                window.location.assign(`${basePath}/all-surveys`);
            } else {
                window.location.assign(`${basePath}/survey`);
            }
        }
    }
}