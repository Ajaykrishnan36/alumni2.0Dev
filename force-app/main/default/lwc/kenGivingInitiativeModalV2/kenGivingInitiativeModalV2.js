import { LightningElement, track } from 'lwc';
import submitCampaignRequest from '@salesforce/apex/KenGiftCampaignController.submitCampaignRequest';
import createContentVersion from '@salesforce/apex/KenCreateContentVersion.createContentVersion';

const CATEGORY_OPTIONS = [
    { label: 'Batch Fund',     value: 'Batch Fund' },
    { label: 'Scholarship',    value: 'Scholarship' },
    { label: 'Infrastructure', value: 'Infrastructure' },
    { label: 'Research',       value: 'Research' },
    { label: 'Athletics',      value: 'Athletics' },
    { label: 'Emergency',      value: 'Emergency' },
    { label: 'General',        value: 'General' }
];

export default class KenGivingInitiativeModalV2 extends LightningElement {
    // form state
    @track title = '';
    @track category = 'Batch Fund';
    @track goalAmount = null;
    @track shortDescription = '';
    @track whyItMatters = '';
    @track beneficiaryGroup = '';
    @track batchAssociation = '';
    @track isReunionLinked = false;
    @track listAsInitiator = true;
    @track inviteBatchmates = true;

    // Cover image upload state — proven ContentVersion pattern (returns a public URL,
    // stored as heroImageUrl and saved to Ken_Gift_Campaign_Request__c.Hero_Image_URL__c).
    MAX_COVER_BYTES = 2 * 1024 * 1024; // 2 MB
    @track coverImageUrl = '';   // public URL returned by createContentVersion
    @track coverImageName = '';
    @track coverUploading = false;
    @track coverError = '';

    @track submitting = false;
    @track errorMsg = '';

    get categoryOptions() { return CATEGORY_OPTIONS; }

    get hasCover() { return !!(this.coverImageUrl && this.coverImageUrl.length); }
    get coverLabel() {
        if (this.coverUploading) return 'Uploading…';
        return this.coverImageName ? this.coverImageName : 'Upload cover image';
    }
    get coverPreviewStyle() {
        const box = 'width:120px;height:72px;border-radius:8px;border:1px solid #e5e7eb;flex:0 0 auto;';
        return this.hasCover
            ? `${box}background-image:url('${String(this.coverImageUrl).replace(/'/g, "\\'")}');background-size:cover;background-position:center;`
            : box;
    }

    // All handlers read from standard HTML DOM events.
    handleTitle(e)            { this.title = e.target.value; }
    handleCategory(e)         { this.category = e.target.value; }
    handleGoal(e)             { this.goalAmount = e.target.value ? Number(e.target.value) : null; }
    handleShortDesc(e)        { this.shortDescription = e.target.value; }
    handleWhy(e)              { this.whyItMatters = e.target.value; }
    handleBeneficiary(e)      { this.beneficiaryGroup = e.target.value; }
    handleBatchAssoc(e)       { this.batchAssociation = e.target.value; }
    handleReunion(e)          { this.isReunionLinked = e.target.checked; }
    handleListInitiator(e)    { this.listAsInitiator = e.target.checked; }
    handleInviteBatchmates(e) { this.inviteBatchmates = e.target.checked; }

    /**
     * Cover image upload — FileReader → base64 → KenCreateContentVersion.createContentVersion,
     * which returns a public URL. We store that URL as heroImageUrl and send it in the payload;
     * KenGiftCampaignController saves it to Ken_Gift_Campaign_Request__c.Hero_Image_URL__c.
     */
    handleCoverPhoto(event) {
        this.coverError = '';
        const file = event && event.target && event.target.files && event.target.files[0];
        if (!file) return;
        if (file.size > this.MAX_COVER_BYTES) {
            this.coverError = 'Image too large (max 2 MB). Please choose a smaller image.';
            event.target.value = '';
            return;
        }
        const fileName = file.name;
        this.coverUploading = true;
        const reader = new FileReader();
        reader.onload = () => {
            const result = String(reader.result || '');
            const idx = result.indexOf('base64,');
            const base64 = idx > -1 ? result.substring(idx + 7) : '';
            if (!base64) { this.coverUploading = false; this.coverError = 'Could not read that image.'; return; }
            createContentVersion({ title: 'GivingCover_' + Date.now() + '_' + fileName, base64String: base64 })
                .then(url => {
                    this.coverUploading = false;
                    if (url && /^https?:\/\//i.test(url)) {
                        this.coverImageUrl = url;
                        this.coverImageName = fileName;
                    } else {
                        this.coverError = 'Cover upload failed: ' + (url || 'unknown error');
                    }
                })
                .catch(err => {
                    this.coverUploading = false;
                    this.coverError = (err && err.body && err.body.message) || 'Cover upload failed.';
                });
        };
        reader.onerror = () => { this.coverUploading = false; this.coverError = 'Could not read that image. Please try another.'; };
        reader.readAsDataURL(file);
    }

    handleRemoveCover() {
        this.coverError = '';
        this.coverImageUrl = '';
        this.coverImageName = '';
        const input = this.template.querySelector('#ini-cover');
        if (input) input.value = '';
    }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }

    /**
     * HTML5 validation — walks native input/textarea/select inside the form and calls
     * reportValidity(). Honors the `required` attribute on each field. Returns true only
     * if every required field passes.
     */
    _validateForm() {
        const fields = this.template.querySelectorAll('input, textarea, select');
        let ok = true;
        fields.forEach(f => {
            // Skip non-form helpers (file input is optional + has no `required`)
            if (typeof f.reportValidity !== 'function') return;
            if (!f.reportValidity()) ok = false;
        });
        return ok;
    }

    handleSubmit() {
        this.errorMsg = '';
        if (!this._validateForm()) {
            this.errorMsg = 'Please complete the required fields highlighted above.';
            return;
        }
        this.submitting = true;
        const payload = {
            title: this.title,
            category: this.category,
            goalAmount: this.goalAmount,
            description: this.shortDescription,
            whyItMatters: this.whyItMatters,
            beneficiaryGroup: this.beneficiaryGroup,
            batchAssociation: this.batchAssociation,
            isReunionLinked: this.isReunionLinked,
            listAsInitiator: this.listAsInitiator,
            inviteBatchmates: this.inviteBatchmates,
            heroImageUrl: this.coverImageUrl || null,
            requestId: this._requestId()
        };
        submitCampaignRequest({ req: payload })
            .then(res => {
                this.submitting = false;
                this.dispatchEvent(new CustomEvent('submitted', {
                    detail: { requestId: res && res.requestId, alreadyExisted: !!(res && res.alreadyExisted) }
                }));
                this.dispatchEvent(new CustomEvent('close'));
            })
            .catch(err => {
                this.submitting = false;
                this.errorMsg = (err && err.body && err.body.message)
                    || 'Could not submit your initiative. Please try again.';
            });
    }

    _requestId() {
        if (!this._reqIdCache) {
            this._reqIdCache = 'INI-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);
        }
        return this._reqIdCache;
    }
}