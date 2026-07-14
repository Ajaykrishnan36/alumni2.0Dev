import { LightningElement, api, track } from 'lwc';
import getLinkedSegmentation from '@salesforce/apex/KenAudienceJunctionController.getLinkedSegmentation';
import linkSegmentationToParent from '@salesforce/apex/KenAudienceJunctionController.linkSegmentationToParent';
import getSavedAudienceDetail from '@salesforce/apex/KenAudienceEngineService.getSavedAudienceDetail';

/**
 * Generic audience configurator step.
 *
 * Renders the saved-audience picker or the segmentation builder for any parent record
 * (Event, Survey, Group, Campaign, …). On mount, looks up an existing junction link for
 * the given parent and, if one exists, opens the builder pre-populated with that audience.
 * All adds are local; the selection is saved as ONE segmentation (and linked to the
 * parent) via the builder's Save button or the wizard's persistCurrentSelection call.
 *
 * Required: parent-object-type ('Event' | 'Survey' | 'Group' | 'Campaign') and
 * parent-record-id.
 *
 * Legacy event-id / survey-id / group-id inputs are accepted for back-compat — if any
 * is set without parent-object-type, the type is inferred.
 */
export default class KenTargetAudience extends LightningElement {
    @api parentObjectType;

    _parentRecordId;
    _existingLookupKey = null;

    @api
    get parentRecordId() { return this._parentRecordId; }
    set parentRecordId(value) {
        this._parentRecordId = value;
        this.maybeLoadExistingSegmentation();
    }

    @api eventId;
    @api surveyId;
    @api groupId;

    // Audience to pre-select for a brand-new record that has no saved segmentation
    // yet (e.g. the group a "Create an Event" was launched from). Applied once.
    _initialAudience = [];
    _initialApplied = false;
    @api
    get initialAudience() { return this._initialAudience; }
    set initialAudience(value) {
        this._initialAudience = Array.isArray(value) ? value : [];
        this.applyInitialAudience();
    }

    @api validationErrors = {};

    @track showAddNewAudienceView = false;
    @track selectedAudienceData = [];
    @track existingSegmentationId = null;
    @track existingSegmentationName = '';
    @track isLoadingExisting = false;
    // true when the current segmentation-id came from PICKING a saved audience — an edit
    // must fork into a new segmentation instead of mutating the shared one.
    @track pickedFromSaved = false;
    _childIsDirty = false;

    /** The currently saved/linked segmentation id (read by wizard hosts). */
    @api
    get segmentationId() {
        return this.existingSegmentationId;
    }

    connectedCallback() {
        this.maybeLoadExistingSegmentation();
        // When there's no parent record yet, no segmentation load happens — seed now.
        // When a parent exists, seeding waits until loadExistingSegmentation confirms
        // there's no saved audience (so the group seeds even for a just-created event
        // whose currentEventId is already set by step 1).
        if (!this.resolvedParentId) {
            this.applyInitialAudience();
        }
    }

    // Seed the pre-selected audience once (e.g. the group a "Create an Event" was
    // launched from), only when nothing is selected and no saved segmentation exists.
    // Reveals the builder view so the seeded item is visible and notifies the wizard.
    applyInitialAudience() {
        if (this._initialApplied) return;
        if (!this._initialAudience || !this._initialAudience.length) return;
        if (this.selectedAudienceData && this.selectedAudienceData.length) return;
        this._initialApplied = true;
        this.selectedAudienceData = [...this._initialAudience];
        this.showAddNewAudienceView = true;
        this.dispatchAudienceChange();
    }

    /**
     * Looks up the parent's linked segmentation once per parent record. The key uses
     * the 15-char id prefix so a 15↔18-char id representing the SAME record never
     * re-triggers the load (which destroys and remounts the builder). The reload is
     * also skipped while the builder holds unsaved edits — the in-progress selection
     * outranks the saved payload, and remounting would silently wipe it (and its
     * dirty flag) right before the wizard's save-gate runs.
     */
    maybeLoadExistingSegmentation() {
        const parentType = this.resolvedParentType;
        const parentId = this.resolvedParentId;
        if (!parentType || !parentId) return;
        const key = parentType + '::' + String(parentId).substring(0, 15);
        if (this._existingLookupKey === key) return;
        this._existingLookupKey = key;
        if (this._childIsDirty) return;
        this.loadExistingSegmentation();
    }

    get resolvedParentType() {
        if (this.parentObjectType) return this.parentObjectType;
        if (this.eventId) return 'Event';
        if (this.surveyId) return 'Survey';
        if (this.groupId) return 'Group';
        return null;
    }

    get resolvedParentId() {
        return this.parentRecordId || this.eventId || this.surveyId || this.groupId || null;
    }

    async loadExistingSegmentation() {
        const parentType = this.resolvedParentType;
        const parentId = this.resolvedParentId;
        if (!parentType || !parentId) return;

        this.isLoadingExisting = true;
        try {
            const segId = await getLinkedSegmentation({ parentObjectType: parentType, parentId });
            if (!segId) {
                // Record exists but has no saved audience yet — seed the pre-selected
                // group (e.g. group → "Create an Event") now that we know it's empty.
                this.applyInitialAudience();
                return;
            }

            this.existingSegmentationId = segId;
            // This is the record's OWN linked segmentation (resume/edit): not a pick.
            // The server still forks on save if the segmentation is shared elsewhere.
            this.pickedFromSaved = false;
            this.showAddNewAudienceView = true;

            try {
                const detail = await getSavedAudienceDetail({ audienceId: segId });
                const payload = detail?.payloadJson ? JSON.parse(detail.payloadJson) : null;
                const items = (payload?.items && Array.isArray(payload.items)) ? payload.items : [];
                this.existingSegmentationName = detail?.name || '';
                this.selectedAudienceData = items;
                this.dispatchAudienceChange();
            } catch (detailErr) {
                console.warn('Failed to load saved audience detail; opened builder empty', detailErr);
                this.dispatchAudienceChange();
            }
        } catch (e) {
            console.warn('Failed to resolve linked segmentation for parent record', e);
        } finally {
            this.isLoadingExisting = false;
        }
    }

    handleAddNewAudience() {
        this.showAddNewAudienceView = true;
    }

    /**
     * A saved audience was picked from the initial picker view. ALL of its items are
     * expanded into the selection. GROUP/INDIVIDUAL items keep their ORIGINAL record
     * ids (the count/SOQL engine resolves them by id); only ALL/CUSTOM ids are UI-only
     * and get regenerated. The picked segmentation is REUSED as-is for the junction
     * link; the first edit forks it into a copy (handled by the builder + server).
     */
    handleSavedAudienceAdded(event) {
        const { audienceId, name, items = [] } = event.detail || {};
        const now = Date.now();
        const base = Array.isArray(this.selectedAudienceData) ? this.selectedAudienceData : [];
        const existingIds = new Set(base.map((i) => i.id));
        const added = [];
        items.forEach((item, idx) => {
            const keepsRealId = item.type === 'GROUP' || item.type === 'INDIVIDUAL';
            const nextId = keepsRealId
                ? item.id
                : `saved_${item.id || item.title || 'item'}_${now}_${idx}`;
            if (existingIds.has(nextId)) return;
            existingIds.add(nextId);
            added.push({ ...item, id: nextId });
        });
        this.selectedAudienceData = [...base, ...added];
        if (audienceId && !this.existingSegmentationId) {
            this.existingSegmentationId = audienceId;
            this.pickedFromSaved = true;
        }
        if (name) {
            this.existingSegmentationName = name;
        }
        this.showAddNewAudienceView = true;
        this.dispatchAudienceChange();
    }

    @api
    async persistCurrentSelection() {
        const audienceCmp = this.template.querySelector('c-ken-portal-audience-selection');
        if (audienceCmp && typeof audienceCmp.persistCurrentSelection === 'function') {
            return audienceCmp.persistCurrentSelection();
        }
        return false;
    }

    // Open the audience save (name) dialog so the user can save the current selection.
    // Ensures the builder view is showing so the child (and its modal) is rendered.
    @api
    openSaveDialog() {
        this.showAddNewAudienceView = true;
        const audienceCmp = this.template.querySelector('c-ken-portal-audience-selection');
        if (audienceCmp && typeof audienceCmp.openSaveDialog === 'function') {
            audienceCmp.openSaveDialog();
        }
    }

    handleAudienceChange(event) {
        if (event && event.detail) {
            const audienceData = event.detail.selectedAudience ?? event.detail.audience ?? event.detail;
            this.selectedAudienceData = audienceData
                ? (Array.isArray(audienceData) ? audienceData : [audienceData])
                : [];
            // Keep the segmentation-id binding in sync with the child (esp. after a fork creates a new id)
            if (event.detail.segmentationId !== undefined) {
                this.existingSegmentationId = event.detail.segmentationId;
            }
            if (event.detail.segmentationName) {
                this.existingSegmentationName = event.detail.segmentationName;
            }
            // A clean (just-saved) state means the segmentation now belongs to this
            // record — stop treating it as a picked shared audience.
            this._childIsDirty = event.detail.isDirty === true;
            if (event.detail.isDirty === false) {
                this.pickedFromSaved = false;
            }
        } else {
            this.selectedAudienceData = [];
        }
        this.dispatchAudienceChange();
    }

    dispatchAudienceChange() {
        this.dispatchEvent(new CustomEvent('audiencechange', {
            detail: {
                selectedAudienceData: this.selectedAudienceData,
                selectedAudience: this.selectedAudienceData
            },
            bubbles: true,
            composed: true
        }));
    }

    /**
     * True when the builder holds edits that are not yet saved to the segmentation.
     * ORs the live builder flag with the wrapper-tracked one: a remounted builder
     * starts clean even though it was re-fed the unsaved selection, so only a
     * successful save (audiencechange with isDirty=false) clears the tracked flag.
     */
    @api
    get hasUnsavedChanges() {
        const audienceCmp = this.template.querySelector('c-ken-portal-audience-selection');
        const childDirty = !!(audienceCmp && audienceCmp.hasUnsavedChanges);
        return childDirty || this._childIsDirty;
    }

    /**
     * True when the current selection is saved as a segmentation and linked to the parent
     * (or saved and merely waiting for the parent record to exist). The builder answers
     * first; on a builder failure the wrapper re-checks server state directly — linking
     * by the known segmentation id, then accepting an already-linked parent — so a
     * segmentation that IS saved can never be reported as unsaved by stale UI state.
     * A DIRTY selection never uses the server fallback: unsaved edits must save (the
     * builder auto-saves them) or the step blocks, otherwise they'd be silently lost.
     */
    @api
    async ensureSegmentationLink() {
        const audienceCmp = this.template.querySelector('c-ken-portal-audience-selection');
        if (audienceCmp && typeof audienceCmp.ensureSegmentationLink === 'function') {
            try {
                if (await audienceCmp.ensureSegmentationLink()) {
                    return true;
                }
            } catch (e) {
                console.warn('Builder segmentation link failed; falling back to server state', e);
            }
            if (this.hasUnsavedChanges) {
                return false;
            }
        }
        const segId = (audienceCmp && audienceCmp.segmentationId) || this.existingSegmentationId;
        const parentType = this.resolvedParentType;
        const parentId = this.resolvedParentId;
        if (!parentType || !parentId) {
            return !!segId;
        }
        if (segId) {
            try {
                await linkSegmentationToParent({
                    parentObjectType: parentType,
                    parentId,
                    segmentationId: segId
                });
                this.existingSegmentationId = segId;
                return true;
            } catch (e) {
                console.warn('Fallback segmentation link failed', e);
            }
        }
        try {
            const linked = await getLinkedSegmentation({ parentObjectType: parentType, parentId });
            if (linked) {
                this.existingSegmentationId = linked;
                return true;
            }
        } catch (e) {
            console.warn('Fallback linked-segmentation lookup failed', e);
        }
        return false;
    }

    /** Back-compat alias for older callers. */
    @api
    async ensureEventSegmentationLink() {
        return this.ensureSegmentationLink();
    }
}