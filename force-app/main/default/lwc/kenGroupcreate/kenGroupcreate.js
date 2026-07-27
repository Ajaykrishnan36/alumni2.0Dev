import { LightningElement, track, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import saveDraftGroup from '@salesforce/apex/KenGroupsController.saveDraftGroup';
import getDraftGroup from '@salesforce/apex/KenGroupsController.getDraftGroup';
import uploadAndGetPublicUrl from '@salesforce/apex/KenFileUploadController.uploadAndGetPublicUrl';
import submitGroupForApproval from '@salesforce/apex/KenGroupsController.submitGroupForApproval';
import getLinkedSegmentation from '@salesforce/apex/KenAudienceJunctionController.getLinkedSegmentation';

const MAX_COVER_SIZE_BYTES = 5 * 1024 * 1024; // 5 MB
const ALLOWED_COVER_TYPES = ['image/png', 'image/jpeg', 'image/jpg'];
const DRAFT_GROUP_ID_KEY = 'createGroupDraftId';
const DRAFT_FORM_KEY = 'createGroupDraftForm';

const LIMIT_NAME = 50;
const LIMIT_TAGS = 100;
const LIMIT_DESC = 1000;
const LIMIT_RULES = 1000;

export default class KenGroupcreate extends NavigationMixin(LightningElement) {
    // Set by the backend New/Edit action override (KenCreateEditGroup). On Edit it
    // carries the Ken_Group__c id; on New it's blank. Portal flows leave it unset
    // and use the sessionStorage draft id instead.
    @api recordId;

    @track currentStep = 1;
    @track isStep1Completed = false;
    @track isStep2Completed = false;
    @track isStep3Completed = false;

    // Portal access gate — hides the form behind an opaque overlay until we confirm
    // "Allow Create Groups" is on, so it never flashes before a redirect.
    @track checkingAccess = false;
    @track accessDenied = false;

    // Draft persistence
    savedGroupId = null;
    @track isSaving = false;
    @track isRestoring = false;
    @track isSubmitting = false;
    @track isSuccess = false;
    @track showSuccessToast = false;

    // Step 1: Setup Group
    @track groupName = '';
    @track tagsInput = '';
    @track whoCanJoin = 'public';
    @track category = 'Group';
    @track groupDescription = '';
    @track rules = '';
    @track hasCoverPhoto = false;
    @track coverImageUrl = '';
    coverImageFile = null; // File object for new uploads not yet pushed to CDN
    @track validationErrors = {};

    // Step 2: Target Audience
    @track selectedAudienceData = [];
    @track audienceSummaryExpandedMap = {};

    get groupIdForAudience() {
        return this.savedGroupId;
    }

    // ── Spinner / button state ────────────────────────────────────────────────

    get showSpinner() {
        return this.isSaving || this.isRestoring || this.isSubmitting;
    }

    get nextButtonLabel() {
        return this.isSaving ? 'Saving...' : 'Next';
    }

    get submitButtonLabel() {
        return this.isSubmitting ? 'Submitting...' : 'Submit';
    }

    get isNextDisabled() {
        return this.isSaving || this.isRestoring;
    }

    get isSubmitDisabled() {
        return this.isSubmitting;
    }

    // ── Character count getters ──────────────────────────────────────────────

    get groupNameCount() { return (this.groupName || '').length; }
    get groupNameLimit() { return LIMIT_NAME; }
    get tagsCount() { return (this.tagsInput || '').length; }
    get tagsLimit() { return LIMIT_TAGS; }
    get descriptionCount() { return (this.groupDescription || '').length; }
    get descriptionLimit() { return LIMIT_DESC; }
    get rulesCount() { return (this.rules || '').length; }
    get rulesLimit() { return LIMIT_RULES; }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    get showAccessGate() {
        return this.checkingAccess || this.accessDenied;
    }

    connectedCallback() {
        if (!this.isBackend) {
            this.checkingAccess = true;
        }
        this._initializeComponent();

        getPrimaryColor()
            .then((color) => {
                if (color?.primaryColor) {
                    document.documentElement.style.setProperty('--primary-color', color.primaryColor);
                }
                if (color?.secondaryColor) {
                    document.documentElement.style.setProperty('--secondary-color', color.secondaryColor);
                }
                if (color?.tertiaryColor) {
                    document.documentElement.style.setProperty('--tertiary-color', color.tertiaryColor);
                }
                this.enforcePortalCreateAccess(color);
            })
            .catch(() => { this.enforcePortalCreateAccess(null); });
    }

    // If "Allow Create Groups" is off, a portal user reaching /create-group directly
    // is bounced back to the Groups page. Backend/internal context is never gated.
    enforcePortalCreateAccess(config) {
        this.checkingAccess = false;
        if (this.isBackend) {
            return;
        }
        if (config && config.createGroups !== false) {
            return;
        }
        this.accessDenied = true;
        let base = '';
        try {
            const seg = (window.location.pathname || '').split('/').filter((s) => s);
            base = seg.length ? '/' + seg[0] : '';
        } catch (e) {
            base = '';
        }
        window.location.assign(`${base}/group`);
    }

    async _initializeComponent() {
        // Backend Edit override passes the record via @api recordId; portal flows use
        // the sessionStorage draft id.
        const storedId = this.recordId || sessionStorage.getItem(DRAFT_GROUP_ID_KEY);
        if (!storedId) {
            // No saved draft — restore any unsaved form state from session
            this._restoreFormFromSession();
            return;
        }

        this.savedGroupId = storedId;
        this.isRestoring = true;
        try {
            // Primary restore: load authoritative data from Salesforce
            const grp = await getDraftGroup({ groupId: storedId });
            if (grp) {
                this.groupName        = grp.Name || '';
                this.tagsInput        = grp.Tags__c || '';
                this.whoCanJoin       = (grp.Group_Type__c || 'public').toLowerCase();
                this.category         = grp.Category__c || 'Group';
                this.groupDescription = grp.Description__c || '';
                this.rules            = grp.Rules__c || '';
                if (grp.Banner_Image_URL__c) {
                    this.coverImageUrl = grp.Banner_Image_URL__c;
                    this.hasCoverPhoto = true;
                }
            }
        } catch (e) {
            // Fallback: restore text fields from sessionStorage form snapshot
            this._restoreFormFromSession();
        } finally {
            this.isRestoring = false;
        }
    }

    _restoreFormFromSession() {
        try {
            const raw = sessionStorage.getItem(DRAFT_FORM_KEY);
            if (!raw) return;
            const form = JSON.parse(raw);
            this.groupName        = form.groupName        || '';
            this.tagsInput        = form.tagsInput        || '';
            this.whoCanJoin       = form.whoCanJoin       || 'public';
            this.category         = form.category         || 'Group';
            this.groupDescription = form.groupDescription || '';
            this.rules            = form.rules            || '';
        } catch (e) { /* ignore */ }
    }

    _saveFormToSession() {
        try {
            const formData = {
                groupName:        this.groupName,
                tagsInput:        this.tagsInput,
                whoCanJoin:       this.whoCanJoin,
                category:         this.category,
                groupDescription: this.groupDescription,
                rules:            this.rules
            };
            sessionStorage.setItem(DRAFT_FORM_KEY, JSON.stringify(formData));
        } catch (e) { /* ignore */ }
    }

    _clearSession() {
        sessionStorage.removeItem(DRAFT_GROUP_ID_KEY);
        sessionStorage.removeItem(DRAFT_FORM_KEY);
    }

    disconnectedCallback() {
        if (this.savedAudienceSearchTimer) {
            clearTimeout(this.savedAudienceSearchTimer);
        }
    }

    // ── Stepper ──────────────────────────────────────────────────────────────

    get stepperItems() {
        const steps = [
            { number: 1, label: 'Setup Group',       completed: this.isStep1Completed },
            { number: 2, label: 'Target Audience',   completed: this.isStep2Completed },
            { number: 3, label: 'Summary',           completed: this.isStep3Completed }
        ];
        const totalSteps = steps.length;
        return steps.map((step) => {
            const isActive    = this.currentStep === step.number;
            const isCompleted = (step.completed || this.currentStep > step.number) && !isActive;
            return {
                ...step,
                isActive,
                isCompleted,
                isLast: step.number === totalSteps,
                statusClass: `step ${isActive ? 'active' : ''} ${isCompleted ? 'completed' : ''}`.trim(),
                lineClass: isActive || isCompleted ? 'step-line active' : 'step-line'
            };
        });
    }

    get stepIndicatorLabel() { return `Step ${this.currentStep} out of 3`; }

    get progressFillStyle() {
        return `width:${Math.min(100, ((this.currentStep - 1) / 2) * 100)}%`;
    }

    get isStep1Active() { return this.currentStep === 1; }
    get isStep2Active() { return this.currentStep === 2; }
    get isStep3Active() { return this.currentStep === 3; }

    // ── Step 1 getters ───────────────────────────────────────────────────────

    get isPublicSelected()  { return this.whoCanJoin === 'public'; }
    get isPrivateSelected() { return this.whoCanJoin === 'private'; }

    // Picklist mirrors Ken_Group__c.Category__c — new values can be added there
    // without any code change here as long as this list is kept in sync.
    get categoryOptions() {
        return [
            { label: 'Group', value: 'Group' },
            { label: 'Chapter', value: 'Chapter' }
        ].map((opt) => ({ ...opt, selected: opt.value === this.category }));
    }

    // ── Step 2: Audience ─────────────────────────────────────────────────────

    get hasSelectedAudience() {
        if (!this.selectedAudienceData) return false;
        if (Array.isArray(this.selectedAudienceData)) return this.selectedAudienceData.length > 0;
        if (this.selectedAudienceData && Array.isArray(this.selectedAudienceData.items)) {
            return this.selectedAudienceData.items.length > 0;
        }
        if (this.selectedAudienceData && typeof this.selectedAudienceData === 'object') {
            return Object.keys(this.selectedAudienceData).length > 0;
        }
        return false;
    }

    normalizeAudienceItems() {
        if (Array.isArray(this.selectedAudienceData)) return this.selectedAudienceData;
        if (this.selectedAudienceData && Array.isArray(this.selectedAudienceData.items)) {
            return this.selectedAudienceData.items;
        }
        if (this.selectedAudienceData && typeof this.selectedAudienceData === 'object') {
            return Object.values(this.selectedAudienceData).filter((item) => !!item);
        }
        return [];
    }

    normalizeAudienceCountsLabels(items) {
        const list = Array.isArray(items) ? items : [];
        return list.map((it) => {
            const item = { ...it };
            let count = null;
            if (Number.isFinite(item.memberCount)) {
                count = item.memberCount;
            } else if (typeof item.memberCount === 'string' && item.memberCount.trim() !== '') {
                const parsed = Number(item.memberCount.trim());
                if (Number.isFinite(parsed)) count = parsed;
            }
            if (count !== null) {
                item.membersLabel = count === 1 ? '1 Member' : `${count} Members`;
                item.memberCount = count;
                return item;
            }
            if (typeof item.membersLabel === 'string' && item.membersLabel.toLowerCase().includes('calculating')) {
                item.membersLabel = item.roleLabel || item.role || 'Audience';
            }
            if (!item.membersLabel) item.membersLabel = 'Audience';
            if (item.memberCount === 0 && !item.membersLabel) item.membersLabel = '0 Members';
            return item;
        });
    }

    syncAudienceSummaryExpanded() {
        const items = this.normalizeAudienceItems();
        const next = { ...(this.audienceSummaryExpandedMap || {}) };
        items.forEach((item, index) => {
            const id = item.id || `aud_${index}`;
            if (next[id] === undefined) next[id] = index === 0;
        });
        this.audienceSummaryExpandedMap = next;
    }

    get audienceSummaryItems() {
        const items = this.normalizeAudienceCountsLabels(this.normalizeAudienceItems());
        const expandedMap = this.audienceSummaryExpandedMap || {};
        return items.map((item, index) => {
            const id       = item.id || `aud_${index}`;
            const expanded = expandedMap[id] === undefined ? index === 0 : !!expandedMap[id];
            const criteria = Array.isArray(item.criteria) ? item.criteria : [];
            const membersLabel = (() => {
                if (item.membersLabel && item.membersLabel.trim()) return item.membersLabel;
                if (Number.isFinite(item.memberCount)) {
                    const c = item.memberCount;
                    return c === 1 ? '1 Member' : `${c} Members`;
                }
                return 'Audience';
            })();
            return {
                ...item,
                id,
                expanded,
                caretClass: expanded ? 'caret-icon caret-up' : 'caret-icon caret-down',
                roleTag:    item.roleLabel || item.role || 'Audience',
                membersTag: membersLabel,
                criteria,
                hasCriteria: criteria.length > 0
            };
        });
    }

    // ── Step 3 Summary getters ───────────────────────────────────────────────

    get hasGroupName()        { return this.groupName        && this.groupName.trim(); }
    get hasTags()             { return (this.tagsInput || '').trim().length > 0; }
    get tagsDisplay()         { return (this.tagsInput || '').trim() || '--'; }
    get whoCanJoinLabel()     { return this.whoCanJoin === 'public' ? 'Public - Anyone can join' : 'Private - Users must request to join'; }
    get categoryLabel()       { return this.category === 'Chapter' ? 'Chapter' : 'Group'; }
    get hasGroupDescription() { return this.groupDescription && this.groupDescription.trim(); }
    get hasRules()            { return this.rules && this.rules.trim(); }

    // ── Cover photo ──────────────────────────────────────────────────────────

    handleCoverPhotoUploadScreen() {
        const fileInput = this.template.querySelector('.hidden-file-input');
        if (fileInput) fileInput.click();
    }

    handleCoverPhotoUpload(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) return;
        if (!ALLOWED_COVER_TYPES.includes(file.type)) {
            this.validationErrors = { ...this.validationErrors, coverPhoto: 'Image format must be PNG or JPEG.' };
            return;
        }
        if (file.size > MAX_COVER_SIZE_BYTES) {
            this.validationErrors = { ...this.validationErrors, coverPhoto: 'Max image size is 5 MB.' };
            return;
        }
        const { coverPhoto: _removed, ...rest } = this.validationErrors;
        this.validationErrors = rest;

        const reader = new FileReader();
        reader.onload = () => {
            this.coverImageUrl  = reader.result; // base64 preview only
            this.hasCoverPhoto  = true;
            this.coverImageFile = file;           // will be uploaded on Next
        };
        reader.readAsDataURL(file);
        event.target.value = '';
    }

    handleDeleteCoverImage() {
        this.coverImageUrl  = '';
        this.hasCoverPhoto  = false;
        this.coverImageFile = null;
        const { coverPhoto: _removed, ...rest } = this.validationErrors;
        this.validationErrors = rest;
    }

    // ── Step 1 field handlers ────────────────────────────────────────────────

    handleGroupNameChange(event) {
        this.groupName = event.target.value || '';
        const { groupName: _r, ...rest } = this.validationErrors;
        this.validationErrors = rest;
        this._saveFormToSession();
    }

    handleTagsInputChange(event) {
        this.tagsInput = event.target.value || '';
        const { tagsInput: _r, ...rest } = this.validationErrors;
        this.validationErrors = rest;
        this._saveFormToSession();
    }

    handleWhoCanJoinChange(event) {
        this.whoCanJoin = event.target.value || 'public';
        this._saveFormToSession();
    }

    handleCategoryChange(event) {
        this.category = event.target.value || 'Group';
        const { category: _r, ...rest } = this.validationErrors;
        this.validationErrors = rest;
        this._saveFormToSession();
    }

    handleGroupDescriptionChange(event) {
        this.groupDescription = event.detail.value || '';
        const { groupDescription: _r, ...rest } = this.validationErrors;
        this.validationErrors = rest;
        this._saveFormToSession();
    }

    handleRulesChange(event) {
        this.rules = event.detail.value || '';
        const { rules: _r, ...rest } = this.validationErrors;
        this.validationErrors = rest;
        this._saveFormToSession();
    }

    // ── Step 2: Audience handlers ────────────────────────────────────────────

    handleAudienceChange(event) {
        const audienceData = event.detail?.selectedAudience ?? event.detail?.audience ?? event.detail;
        this.selectedAudienceData = audienceData ? audienceData : [];
        this.selectedAudienceData = this.normalizeAudienceCountsLabels(this.selectedAudienceData);
        this.syncAudienceSummaryExpanded();
    }


    handleToggleAudienceSummary(event) {
        const id = event.currentTarget?.dataset?.id;
        if (!id) return;
        const next = { ...(this.audienceSummaryExpandedMap || {}) };
        next[id] = !next[id];
        this.audienceSummaryExpandedMap = next;
    }

    // ── Edit steps ───────────────────────────────────────────────────────────

    handleEditStep1() { this.currentStep = 1; }
    handleEditStep2() { this.currentStep = 2; }

    // ── Validation ───────────────────────────────────────────────────────────

    _validateStep1() {
        const errors = {};
        const name = (this.groupName || '').trim();
        if (!name) {
            errors.groupName = 'Group name is required.';
        } else if (name.length > LIMIT_NAME) {
            errors.groupName = `Group name cannot exceed ${LIMIT_NAME} characters.`;
        }

        const tags = (this.tagsInput || '').trim();
        if (tags.length > LIMIT_TAGS) {
            errors.tagsInput = `Tags cannot exceed ${LIMIT_TAGS} characters.`;
        }

        if (!(this.category || '').trim()) {
            errors.category = 'Category is required.';
        }

        // Description and Rules hold the editor's HTML — measure the VISIBLE
        // text, not the markup, so formatting tags and empty-editor boilerplate
        // (<div><br></div> etc.) never trip the limit on an optional field.
        if (this._plainTextLen(this.groupDescription) > LIMIT_DESC) {
            errors.groupDescription = `Description cannot exceed ${LIMIT_DESC} characters.`;
        }

        if (this._plainTextLen(this.rules) > LIMIT_RULES) {
            errors.rules = `Rules cannot exceed ${LIMIT_RULES} characters.`;
        }

        this.validationErrors = errors;
        return Object.keys(errors).length === 0;
    }

    // Visible-text length of an HTML string (mirrors kenRichTextEditor._plainLen).
    _plainTextLen(html) {
        const helper = document.createElement('div');
        helper.innerHTML = html || '';
        return (helper.textContent || '').replace(/\s+/g, ' ').trim().length;
    }

    // ── Image upload helper ──────────────────────────────────────────────────

    _toBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onloadend = () => {
                const dataUrl = reader.result || '';
                const parts   = String(dataUrl).split(',');
                resolve(parts[1] || '');
            };
            reader.onerror = reject;
            reader.readAsDataURL(file);
        });
    }

    async _uploadCoverIfNeeded() {
        // Already a CDN URL — nothing to do
        if (!this.coverImageFile) {
            return this.coverImageUrl && this.coverImageUrl.startsWith('http')
                ? this.coverImageUrl
                : null;
        }
        const base64Content = await this._toBase64(this.coverImageFile);
        const fileName      = this.coverImageFile.name;
        const cdnUrl        = await uploadAndGetPublicUrl({ fileName, base64Content });
        // Update local state so subsequent saves reuse the CDN URL
        this.coverImageUrl  = cdnUrl;
        this.coverImageFile = null;
        return cdnUrl;
    }

    // ── Navigation ───────────────────────────────────────────────────────────

    async handleNextStep() {
        if (this.currentStep === 1) {
            if (!this._validateStep1()) return;

            this.isSaving = true;
            try {
                const bannerUrl = await this._uploadCoverIfNeeded();
                const groupId   = await saveDraftGroup({
                    groupId:      this.savedGroupId || null,
                    name:         this.groupName.trim(),
                    // Store null (not <div><br></div> boilerplate) when the
                    // editor has no visible text.
                    description:  this._plainTextLen(this.groupDescription) > 0 ? this.groupDescription.trim() : null,
                    groupType:    this.whoCanJoin,
                    category:     this.category || 'Group',
                    bannerImageUrl: bannerUrl,
                    tags:         (this.tagsInput || '').trim() || null,
                    rules:        this._plainTextLen(this.rules) > 0 ? this.rules.trim() : null
                });
                this.savedGroupId = groupId;
                sessionStorage.setItem(DRAFT_GROUP_ID_KEY, groupId);
                this._saveFormToSession();
            } catch (e) {
                this.showErrorToast('Error', 'Failed to save group draft. Please try again.');
                return;
            } finally {
                this.isSaving = false;
            }

            this.isStep1Completed = true;

        } else if (this.currentStep === 2) {
            if (!this.hasSelectedAudience) {
                this.showErrorToast('Error', 'Please select at least one target audience.');
                return;
            }

            // The audience must be SAVED as a segmentation and LINKED to the group
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
                this.showErrorToast('Error', 'Please save your target audience to continue.');
                if (audienceWrapper && typeof audienceWrapper.openSaveDialog === 'function') {
                    audienceWrapper.openSaveDialog();
                }
                return;
            }

            this.isStep2Completed = true;
        }

        if (this.currentStep < 3) {
            this.currentStep++;
        }
    }

    /**
     * Server-truth fallback for the step-2 audience gate, consulted only when the
     * selection has NO unsaved edits (a dirty selection must save or block). The
     * wrapper/builder can report false from stale client state (or throw) even after
     * a successful save, so before blocking we accept the step when the group already
     * has a linked segmentation — or the audience is saved and the group record does
     * not exist yet.
     */
    async isAudienceLinkedOnServer(audienceWrapper) {
        const savedSegId = audienceWrapper ? audienceWrapper.segmentationId : null;
        const parentId = this.savedGroupId;
        if (!parentId) {
            return !!savedSegId;
        }
        try {
            const linked = await getLinkedSegmentation({ parentObjectType: 'Group', parentId });
            return !!linked;
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Linked-audience fallback check failed', e);
            return false;
        }
    }

    handlePreviousStep() {
        if (this.currentStep > 1) this.currentStep--;
    }

    // True when running in the internal/backend Lightning app rather than the
    // community — used to route navigation to standard record/list pages instead
    // of community named pages (which don't resolve in the backend).
    get isBackend() {
        return typeof window !== 'undefined'
            && !!window.location
            && (window.location.pathname || '').indexOf('/lightning/') !== -1;
    }

    _navigateToGroupsList() {
        if (this.isBackend) {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: { objectApiName: 'Ken_Group__c', actionName: 'list' },
                state: { filterName: 'Recent' }
            });
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'group__c' }
        });
    }

    handleCancel() {
        this._clearSession();
        this._navigateToGroupsList();
    }

    async handleSubmit() {
        if (!this.savedGroupId) {
            this.showErrorToast('Error', 'No group draft found. Please start over.');
            return;
        }
        this.isSubmitting = true;
        try {
            await submitGroupForApproval({ groupId: this.savedGroupId });
            this._clearSession();
            this.showSuccessToast = true;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                if (this.isBackend && this.savedGroupId) {
                    this[NavigationMixin.Navigate]({
                        type: 'standard__recordPage',
                        attributes: {
                            recordId: this.savedGroupId,
                            objectApiName: 'Ken_Group__c',
                            actionName: 'view'
                        }
                    });
                    return;
                }
                this[NavigationMixin.Navigate]({
                    type: 'comm__namedPage',
                    attributes: { name: 'created_groups__c' }
                });
            }, 3000);
        } catch (e) {
            const msg = e?.body?.message || 'Failed to submit group. Please try again.';
            this.showErrorToast('Error', msg);
        } finally {
            this.isSubmitting = false;
        }
    }

    handleGoToGroups() {
        this._navigateToGroupsList();
    }

    showErrorToast(title, message) {
        this.dispatchEvent(
            new CustomEvent('error', {
                detail: { title, message },
                bubbles: true,
                composed: true
            })
        );
    }
}