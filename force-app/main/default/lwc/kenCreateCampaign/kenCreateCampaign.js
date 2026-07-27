import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { getPortalConfigs } from 'c/kenThemeConfig';
import createCampaign             from '@salesforce/apex/KenFundraiseController.createCampaign';
import updateCampaign             from '@salesforce/apex/KenFundraiseController.updateCampaign';
import finalizeAndSubmitCampaign  from '@salesforce/apex/KenFundraiseController.finalizeAndSubmitCampaign';
import getCampaignById            from '@salesforce/apex/KenFundraiseController.getCampaignById';
import getFundraiseCategories     from '@salesforce/apex/KenFundraiseController.getFundraiseCategories';
import getLinkedSegmentation      from '@salesforce/apex/KenAudienceJunctionController.getLinkedSegmentation';

export default class KenCreateCampaign extends NavigationMixin(LightningElement) {
    // Portal access gate — the form stays hidden behind an opaque overlay until we
    // confirm "Allow Create Fundraise" is on, so it never flashes before a redirect.
    @track checkingAccess = false;
    @track accessDenied = false;
    @track currentStep = 1;
    @track isStep1Completed = false;
    @track isStep2Completed = false;
    @track isStep3Completed = false;

    // Step 1 fields
    @track campaignTitle = '';
    @track categoryId = '';
    @track description = '';
    @track currency = 'INR';
    @track fundraisingGoal = '';
    @track collectionMethod = 'internal';
    @track externalLink = '';
    @track startDate = '';
    @track endDate = '';
    @track coverPhotoUrl = null;

    // Validation errors
    @track step1Errors = {};

    // Step 2
    @track campaignId = null;       // real SF record ID — null until Step 1→2 transition (create) or set on mount (edit)
    @track selectedAudienceData = [];
    @track audienceSummaryExpandedMap = {};
    @track step2Error = null;

    // Submit / transition state
    @track isSubmitting = false;
    @track isProceeding = false;    // true while creating the campaign draft before Step 2
    @track submitError = null;

    // Edit mode
    @track _isEditMode = false;
    @track _isLoadingData = false;
    @track _updateSuccess = false;
    _editCampaignId = null;
    _successTimer = null;

    // Categories (from Ken_Fundraise_Category__c)
    @track _categories = [];

    @wire(getFundraiseCategories)
    wiredCategories({ data }) {
        this._categories = data || [];
    }

    connectedCallback() {
        this._resetState();
        if (this.portalBase !== null) {
            this.checkingAccess = true;
        }
        getPortalConfigs().then(configs => {
            if (configs) {
                document.documentElement.style.setProperty('--primary-color', configs.primaryColor || '#1E40AF');
                document.documentElement.style.setProperty('--secondary-color', configs.secondaryColor || '#60A563');
            }
            this.enforcePortalCreateAccess(configs);
        }).catch(() => { this.enforcePortalCreateAccess(null); });
    }

    get showAccessGate() {
        return this.checkingAccess || this.accessDenied;
    }

    // Portal base path ('' in the internal Lightning app, '/<site>' on a community
    // page); null signals a non-portal context that should never be gated.
    get portalBase() {
        try {
            const path = (typeof window !== 'undefined' && window.location && window.location.pathname)
                ? window.location.pathname : '';
            if (!path || path.indexOf('/lightning/') !== -1) {
                return null;
            }
            const seg = path.split('/').filter((s) => s);
            return seg.length ? '/' + seg[0] : '';
        } catch (e) {
            return null;
        }
    }

    // If "Allow Create Fundraise" is off, a portal user reaching /create-campaign
    // directly is bounced back to the Fundraise page.
    enforcePortalCreateAccess(config) {
        this.checkingAccess = false;
        const base = this.portalBase;
        if (base === null) {
            return;
        }
        if (config && config.createFundraise !== false) {
            return;
        }
        this.accessDenied = true;
        window.location.assign(`${base.replace(/\/+$/, '')}/fundraise`);
    }

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        const campaignId = ref?.state?.recordId || ref?.state?.c__campaignId;
        if (campaignId && campaignId !== this._editCampaignId) {
            this._editCampaignId = campaignId;
            this._isEditMode = true;
            this.campaignId = campaignId;
            this._loadExistingData(campaignId);
        }
    }

    async _loadExistingData(campaignId) {
        this._isLoadingData = true;
        try {
            const data = await getCampaignById({ campaignId });
            if (data) {
                this.campaignTitle    = data.name            || '';
                this.categoryId       = data.categoryId       || '';
                this.description      = data.description      || '';
                this.currency         = data.currencyCode     || 'INR';
                this.fundraisingGoal  = data.fundraisingGoal  != null ? String(data.fundraisingGoal) : '';
                this.collectionMethod = data.collectionMethod || 'internal';
                this.externalLink     = data.externalLink     || '';
                this.startDate        = data.startDate        || '';
                this.endDate          = data.endDate          || '';
                this.coverPhotoUrl    = data.coverImage       || null;
            }
        } catch (e) {
            // silently ignore — form stays blank if load fails
        } finally {
            this._isLoadingData = false;
        }
    }

    _resetState() {
        this.currentStep = 1;
        this.isStep1Completed = false;
        this.isStep2Completed = false;
        this.isStep3Completed = false;
        this.campaignTitle = '';
        this.categoryId = '';
        this.description = '';
        this.currency = 'INR';
        this.fundraisingGoal = '';
        this.collectionMethod = 'internal';
        this.externalLink = '';
        this.startDate = '';
        this.endDate = '';
        this.coverPhotoUrl = null;
        this.step1Errors = {};
        if (!this._isEditMode) this.campaignId = null;
        this.selectedAudienceData = [];
        this.audienceSummaryExpandedMap = {};
        this.step2Error = null;
        this.isSubmitting = false;
        this.isProceeding = false;
        this.submitError = null;
    }

    // ── Computed getters ─────────────────────────────────────────────────────

    get isEditMode() { return this._isEditMode; }

    get pageTitleLabel() { return this._isEditMode ? 'Edit Campaign' : '1. Setup Campaign'; }

    get nextButtonLabel() {
        if (this.isProceeding) return 'Please wait…';
        return 'Next';
    }

    get step2NextBtnClass() {
        return this.step2Error ? 'btn-primary btn-audience-error' : 'btn-primary';
    }

    get submitButtonLabel() {
        if (this._updateSuccess) return 'Updated ✓';
        if (this.isSubmitting) return this._isEditMode ? 'Updating...' : 'Submitting...';
        return this._isEditMode ? 'Update' : 'Submit Campaign';
    }

    get submitButtonClass() {
        return this._updateSuccess ? 'btn-primary btn-updated-success' : 'btn-primary';
    }

    // ── Field class getters ──────────────────────────────────────────────────
    get titleFieldClass()        { return `form-field${this.step1Errors.campaignTitle    ? ' has-error' : ''}`; }
    get categoryFieldClass()     { return `form-field${this.step1Errors.category         ? ' has-error' : ''}`; }
    get descriptionFieldClass()  { return `form-field${this.step1Errors.description      ? ' has-error' : ''}`; }
    get goalFieldClass()          { return `form-field${this.step1Errors.fundraisingGoal  ? ' has-error' : ''}`; }
    get startDateFieldClass()     { return `form-field${this.step1Errors.startDate        ? ' has-error' : ''}`; }
    get endDateFieldClass()       { return `form-field${this.step1Errors.endDate          ? ' has-error' : ''}`; }
    get externalLinkFieldClass()  { return `form-field${this.step1Errors.externalLink     ? ' has-error' : ''}`; }

    // ── Category / currency ──────────────────────────────────────────────────
    get categoryOptions() {
        return (this._categories || []).map(c => ({
            label: c.name,
            value: c.id,
            selected: this.categoryId === c.id
        }));
    }

    get category() {
        const match = (this._categories || []).find(c => c.id === this.categoryId);
        return match ? match.name : '';
    }

    get isNoCategorySelected() { return !this.categoryId; }

    get currencyOptions() {
        return [
            { label: '₹  Indian Rupees (INR)', value: 'INR' },
            { label: '$  US Dollar (USD)',      value: 'USD' },
            { label: '€  Euro (EUR)',           value: 'EUR' },
            { label: '£  British Pound (GBP)',  value: 'GBP' }
        ].map(o => ({ ...o, selected: this.currency === o.value }));
    }

    get currencySymbol() {
        return { INR: '₹', USD: '$', EUR: '€', GBP: '£' }[this.currency] || '₹';
    }

    get currencyLabel() {
        return { INR: 'Indian Rupee', USD: 'US Dollar', EUR: 'Euro', GBP: 'British Pound' }[this.currency] || this.currency;
    }

    get formattedGoal() {
        if (!this.fundraisingGoal) return '-';
        const num = Number(this.fundraisingGoal);
        return isNaN(num) ? String(this.fundraisingGoal) : num.toLocaleString('en-IN');
    }

    get formattedStartDate() { return this._formatDate(this.startDate); }
    get formattedEndDate()   { return this._formatDate(this.endDate); }

    _formatDate(dateStr) {
        if (!dateStr) return '-';
        const months = ['January','February','March','April','May','June',
                        'July','August','September','October','November','December'];
        const parts = dateStr.split('-').map(Number);
        if (parts.length !== 3) return dateStr;
        const [year, month, day] = parts;
        return `${day} ${months[month - 1]}, ${year}`;
    }

    get collectionMethodLabel() {
        return this.collectionMethod === 'external' ? 'External fundraising link' : 'Within the Alumni Community';
    }

    get hasSelectedAudience() {
        if (!this.selectedAudienceData) return false;
        if (Array.isArray(this.selectedAudienceData)) return this.selectedAudienceData.length > 0;
        if (typeof this.selectedAudienceData === 'object') {
            if (Array.isArray(this.selectedAudienceData.items)) return this.selectedAudienceData.items.length > 0;
            return Object.keys(this.selectedAudienceData).length > 0;
        }
        return false;
    }

    get audienceSummaryItems() {
        const items = this._normalizeAudienceCounts(this._normalizeAudienceItems());
        const expandedMap = this.audienceSummaryExpandedMap || {};
        return items.map((item, index) => {
            const id = item.id || `aud_${index}`;
            const expanded = expandedMap[id] === undefined ? true : !!expandedMap[id];
            const criteria = Array.isArray(item.criteria) ? item.criteria : [];
            const membersLabel = (item.membersLabel && item.membersLabel.trim())
                ? item.membersLabel
                : (Number.isFinite(item.memberCount)
                    ? (item.memberCount === 1 ? '1 Member' : `${item.memberCount} Members`)
                    : 'Audience');
            return {
                ...item, id, expanded,
                caretClass: expanded ? 'caret-icon caret-up' : 'caret-icon caret-down',
                roleTag: item.roleLabel || item.role || 'Audience',
                membersTag: membersLabel,
                criteria,
                hasCriteria: criteria.length > 0
            };
        });
    }

    _normalizeAudienceItems() {
        if (Array.isArray(this.selectedAudienceData)) return this.selectedAudienceData;
        if (this.selectedAudienceData && Array.isArray(this.selectedAudienceData.items)) return this.selectedAudienceData.items;
        if (this.selectedAudienceData && typeof this.selectedAudienceData === 'object') {
            return Object.values(this.selectedAudienceData).filter(i => !!i);
        }
        return [];
    }

    _normalizeAudienceCounts(items) {
        return (Array.isArray(items) ? items : []).map(it => {
            const item = { ...it };
            let count = null;
            if (Number.isFinite(item.memberCount)) {
                count = item.memberCount;
            } else if (typeof item.memberCount === 'string' && item.memberCount.trim()) {
                const parsed = Number(item.memberCount.trim());
                if (Number.isFinite(parsed)) count = parsed;
            }
            if (count !== null) {
                item.membersLabel = count === 1 ? '1 Member' : `${count} Members`;
                item.memberCount = count;
            } else if (!item.membersLabel || item.membersLabel.toLowerCase().includes('calculating')) {
                item.membersLabel = 'Audience';
            }
            return item;
        });
    }

    get isInternalCollection() { return this.collectionMethod === 'internal'; }
    get isExternalCollection()  { return this.collectionMethod === 'external'; }

    get isStep1Active() { return this.currentStep === 1; }
    get isStep2Active() { return this.currentStep === 2; }
    get isStep3Active() { return this.currentStep === 3; }

    get contentClass() {
        return `component-content${(this.currentStep === 2 || this.currentStep === 3) ? ' content-full' : ''}`;
    }

    // ── File upload ──────────────────────────────────────────────────────────
    handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = (e) => { this.coverPhotoUrl = e.target.result; };
        reader.readAsDataURL(file);
    }

    handleRemoveCover(event) {
        event.stopPropagation();
        this.coverPhotoUrl = null;
    }

    // ── Step 1 field handlers ────────────────────────────────────────────────
    handleTitleChange(event) {
        this.campaignTitle = event.target.value;
        if (this.step1Errors.campaignTitle) this.step1Errors = { ...this.step1Errors, campaignTitle: null };
    }
    handleCategoryChange(event) {
        this.categoryId = event.target.value;
        if (this.step1Errors.category) this.step1Errors = { ...this.step1Errors, category: null };
    }
    handleDescriptionChange(event) {
        this.description = event.target.value;
        if (this.step1Errors.description) this.step1Errors = { ...this.step1Errors, description: null };
    }
    handleCurrencyChange(event) { this.currency = event.target.value; }
    handleGoalChange(event) {
        this.fundraisingGoal = event.target.value;
        if (this.step1Errors.fundraisingGoal) this.step1Errors = { ...this.step1Errors, fundraisingGoal: null };
    }
    handleCollectionMethodChange(event) {
        this.collectionMethod = event.target.value;
        if (this.step1Errors.externalLink) this.step1Errors = { ...this.step1Errors, externalLink: null };
    }
    handleExternalLinkChange(event) {
        this.externalLink = event.target.value;
        if (this.step1Errors.externalLink) this.step1Errors = { ...this.step1Errors, externalLink: null };
    }
    handleGoLink() {
        if (this.externalLink) window.open(this.externalLink, '_blank');
    }
    handleStartDateChange(event) {
        this.startDate = event.target.value;
        if (this.step1Errors.startDate) this.step1Errors = { ...this.step1Errors, startDate: null };
    }
    handleEndDateChange(event) {
        this.endDate = event.target.value;
        if (this.step1Errors.endDate) this.step1Errors = { ...this.step1Errors, endDate: null };
    }

    // ── Validation ───────────────────────────────────────────────────────────
    validateStep1() {
        const errors = {};
        if (!this.campaignTitle.trim())   errors.campaignTitle   = 'Title is required';
        if (!this.categoryId)             errors.category        = 'Please select a category';
        if (!this.description.trim())     errors.description     = 'Description is required';
        if (!this.fundraisingGoal)        errors.fundraisingGoal = 'Fundraising goal is required';
        if (this.collectionMethod === 'external' && !this.externalLink.trim())
                                          errors.externalLink    = 'Please paste the fundraiser link';
        if (!this.startDate)              errors.startDate       = 'Start date is required';
        if (!this.endDate)                errors.endDate         = 'End date is required';
        this.step1Errors = errors;
        if (Object.keys(errors).length > 0) {
            const fieldOrder = ['campaignTitle', 'category', 'description', 'fundraisingGoal', 'externalLink', 'startDate', 'endDate'];
            const firstError = fieldOrder.find(f => errors[f]);
            if (firstError) {
                const el = this.template.querySelector(`[data-field-id="${firstError}"]`);
                if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
            return false;
        }
        return true;
    }

    // ── Step 2 ───────────────────────────────────────────────────────────────
    handleAudienceChange(event) {
        const d = event.detail || {};
        const audience = d.selectedAudience ?? d.selectedAudienceData ?? d.audience;
        this.selectedAudienceData = Array.isArray(audience) ? audience : [];
        const audienceCmp = this.template.querySelector('c-ken-target-audience');
        if (this.hasSelectedAudience || (audienceCmp && !!audienceCmp.segmentationId)) this.step2Error = null;
    }

    handleToggleAudienceSummary(event) {
        const id = event.currentTarget?.dataset?.id;
        if (!id) return;
        const map = this.audienceSummaryExpandedMap || {};
        const currentExpanded = map[id] === undefined ? true : !!map[id];
        this.audienceSummaryExpandedMap = { ...map, [id]: !currentExpanded };
    }

    // ── Navigation ───────────────────────────────────────────────────────────
    async handleNext() {
        if (this.currentStep === 1) {
            if (!this.validateStep1()) return;

            // In create mode, create the campaign record NOW so Step 2 has a real ID.
            // This is what makes kenTargetAudience.linkSegmentationToParent work (needs a parent ID).
            // In edit mode campaignId is already set, so we skip this.
            if (!this._isEditMode && !this.campaignId) {
                this.isProceeding = true;
                this.submitError = null;
                try {
                    const newId = await createCampaign({
                        request: {
                            name:             this.campaignTitle,
                            categoryId:       this.categoryId,
                            description:      this.description,
                            currencyCode:     this.currency,
                            fundraisingGoal:  this.fundraisingGoal ? Number(this.fundraisingGoal) : null,
                            collectionMethod: this.collectionMethod,
                            externalLink:     this.externalLink || null,
                            startDate:        this.startDate,
                            endDate:          this.endDate,
                            coverImageUrl:    this.coverPhotoUrl || null,
                            segmentationIds:  []
                        }
                    });
                    this.campaignId = newId;
                } catch (e) {
                    this.isProceeding = false;
                    this.submitError = e?.body?.message || 'Failed to proceed. Please try again.';
                    return;
                }
                this.isProceeding = false;
            }

            this.isStep1Completed = true;
            this.currentStep = 2;

        } else if (this.currentStep === 2) {
            const audienceCmp = this.template.querySelector('c-ken-target-audience');
            const hasLinked = audienceCmp && !!audienceCmp.segmentationId;
            if (!this.hasSelectedAudience && !hasLinked) {
                this.step2Error = 'Please select or create an audience before proceeding.';
                return;
            }
            // The audience must be SAVED as a segmentation and LINKED to the campaign
            // before advancing. Edited-after-save selections re-save automatically;
            // a never-saved selection blocks and opens the save dialog.
            let audienceLinked = false;
            if (audienceCmp) {
                try {
                    if (typeof audienceCmp.persistCurrentSelection === 'function') {
                        await audienceCmp.persistCurrentSelection();
                    }
                    if (typeof audienceCmp.ensureSegmentationLink === 'function') {
                        audienceLinked = await audienceCmp.ensureSegmentationLink();
                    }
                } catch (e) {
                    // eslint-disable-next-line no-console
                    console.warn('Audience persistence/link failed', e);
                    audienceLinked = false;
                }
            }
            if (!audienceLinked && !(audienceCmp && audienceCmp.hasUnsavedChanges)) {
                audienceLinked = await this.isAudienceLinkedOnServer(audienceCmp);
            }
            if (!audienceLinked) {
                this.step2Error = 'Please save your target audience to continue.';
                if (audienceCmp && typeof audienceCmp.openSaveDialog === 'function') {
                    audienceCmp.openSaveDialog();
                }
                return;
            }
            this.step2Error = null;
            this.isStep2Completed = true;
            this.currentStep = 3;
        }
    }

    /**
     * Server-truth fallback for the step-2 audience gate, consulted only when the
     * selection has NO unsaved edits (a dirty selection must save or block). The
     * wrapper/builder can report false from stale client state (or throw) even after
     * a successful save, so before blocking we accept the step when the campaign
     * already has a linked segmentation — or the audience is saved and the campaign
     * record does not exist yet.
     */
    async isAudienceLinkedOnServer(audienceCmp) {
        const savedSegId = audienceCmp ? audienceCmp.segmentationId : null;
        const parentId = this.campaignId;
        if (!parentId) {
            return !!savedSegId;
        }
        try {
            const linked = await getLinkedSegmentation({ parentObjectType: 'Campaign', parentId });
            return !!linked;
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Linked-audience fallback check failed', e);
            return false;
        }
    }

    handleBack() {
        if (this.currentStep > 1) this.currentStep--;
    }

    handleCancel() {
        if (this.campaignId) {
            // Navigate to the campaign detail (works for both edit and create-then-cancel)
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: { name: 'campaign_detail__c' },
                state: { recordId: this.campaignId }
            });
        } else {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: { name: 'fundraise__c' }
            });
        }
    }

    handleSubmit() {
        const campaignId = this.campaignId || this._editCampaignId;
        if (this.isSubmitting || !campaignId) return;
        this.isSubmitting = true;
        this.submitError = null;

        const apexRequest = {
            campaignId,
            request: {
                name:             this.campaignTitle,
                categoryId:       this.categoryId,
                description:      this.description,
                currencyCode:     this.currency,
                fundraisingGoal:  this.fundraisingGoal ? Number(this.fundraisingGoal) : null,
                collectionMethod: this.collectionMethod,
                externalLink:     this.externalLink || null,
                startDate:        this.startDate,
                endDate:          this.endDate,
                coverImageUrl:    this.coverPhotoUrl || null,
                segmentationIds:  []
            }
        };

        // Both create and edit use finalizeAndSubmitCampaign so edits re-trigger approval.
        const apexCall = finalizeAndSubmitCampaign(apexRequest);

        apexCall
            .then(() => {
                this.isSubmitting = false;
                if (this._isEditMode) {
                    this._updateSuccess = true;
                    const navId = campaignId;
                    this._successTimer = setTimeout(() => {
                        this._updateSuccess = false;
                        this[NavigationMixin.Navigate]({
                            type: 'comm__namedPage',
                            attributes: { name: 'campaign_detail__c' },
                            state: { recordId: navId }
                        });
                    }, 1500);
                } else {
                    this.isStep3Completed = true;
                    this[NavigationMixin.Navigate]({
                        type: 'comm__namedPage',
                        attributes: { name: 'campaign_detail__c' },
                        state: { recordId: this.campaignId }
                    });
                }
            })
            .catch(error => {
                this.isSubmitting = false;
                this.submitError = (error && error.body && error.body.message)
                    ? error.body.message
                    : 'Something went wrong. Please try again.';
            });
    }

    disconnectedCallback() {
        if (this._successTimer) clearTimeout(this._successTimer);
    }

    handleEditStep1() { this.currentStep = 1; }
    handleEditStep2() { this.currentStep = 2; }
}