import { LightningElement, track } from 'lwc';
import createContentVersion from '@salesforce/apex/KenCreateContentVersion.createContentVersion';

const STEP_LABELS = ['Basics', 'Rules', 'Audience', 'Summary'];

export default class KenGroupCreateWizardV2 extends LightningElement {
    @track step = 0;
    @track name = '';
    @track desc = '';
    @track tags = '';
    @track rules = '';
    @track visibility = 'public';

    // Target Audience — captured live from the canonical builder
    // (<c-ken-event-step-details-v2>) via valuechange and carried as `audienceData`.
    @track audienceData = null;

    // Bug G — cover upload
    @track bannerUrl = '';
    @track uploading = false;
    cover = 'linear-gradient(135deg,#3061FF,#9747FF)';

    // Cover-upload error surface (kept; reused by the cover uploader).
    @track batchError = '';

    get steps() {
        return STEP_LABELS.map((label, i) => {
            let cls = 'wstep';
            if (i === this.step) cls += ' wstep--active';
            if (i < this.step) cls += ' wstep--done';
            return { id: i, num: i + 1, label, cssClass: cls };
        });
    }
    get progressStyle() { return `width:${Math.round(((this.step + 1) / 4) * 100)}%`; }
    get stepCounter() { return `Step ${this.step + 1} of 4`; }
    get isBasics() { return this.step === 0; }
    get isRules() { return this.step === 1; }
    get isAudience() { return this.step === 2; }
    get isSummary() { return this.step === 3; }
    get nextLabel() { return this.step === 3 ? 'Submit' : 'Next'; }
    get backDisabled() { return this.step === 0; }

    // Cover preview: uploaded image if present, else the gradient.
    get coverStyle() {
        return this.bannerUrl
            ? `background-image:url('${this.bannerUrl.replace(/'/g, "\\'")}');background-size:cover;background-position:center;`
            : `background:${this.cover}`;
    }

    // QA Bug D — "Who can join" Public/Private had static classes so clicks showed no
    // selected state (read as "not clickable"). Bind computed active classes.
    get visibilityPublicClass()  { return this.visibility === 'public'  ? 'radio-btn radio-btn--active' : 'radio-btn'; }
    get visibilityPrivateClass() { return this.visibility === 'private' ? 'radio-btn radio-btn--active' : 'radio-btn'; }
    get visibilityLabel() { return this.visibility === 'private' ? 'Private — request to join' : 'Public — anyone can join'; }
    // Summary line — counts what the shared audience builder captured.
    get audienceSummary() {
        const a = this.audienceData;
        if (!a) return 'Not configured';
        const n = (a.roles || []).length + (a.groups || []).length + (a.individuals || []).length + (a.saved || []).length;
        return n ? `${n} audience selection(s)` : 'No audience selected';
    }

    handleField(event) {
        const f = event.currentTarget.dataset.field;
        if (!f) return;
        this[f] = event.target.value;
    }
    handleVisibility(event) { this.visibility = event.currentTarget.dataset.value; }

    // ---- Cover upload (Bug G) ----
    handleCover(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) return;
        this.batchError = '';
        this.uploading = true;
        const reader = new FileReader();
        reader.onload = () => {
            const base64 = (reader.result || '').toString().split(',')[1] || '';
            createContentVersion({ title: 'GroupCover_' + Date.now() + '_' + file.name, base64String: base64 })
                .then(url => {
                    this.uploading = false;
                    if (url && /^https?:\/\//i.test(url)) this.bannerUrl = url;
                    else this.batchError = 'Cover upload failed: ' + (url || 'unknown error');
                })
                .catch(err => {
                    this.uploading = false;
                    // eslint-disable-next-line no-console
                    console.error('createContentVersion error', err);
                    this.batchError = (err && err.body && err.body.message) || 'Cover upload failed.';
                });
        };
        reader.readAsDataURL(file);
    }

    // ---- Edit jump links (Bug E) ----
    goToStep(event) {
        const n = Number(event.currentTarget.dataset.step);
        if (n >= 0 && n <= 3) this.step = n;
    }

    handleBack() { if (this.step > 0) this.step -= 1; }

    // Live audience capture from the canonical builder (c-ken-event-step-details-v2).
    handleAudienceChange(event) {
        const { field, value } = event.detail || {};
        if (field === 'audienceDetail') {
            this.audienceData = value;
        }
    }

    handleNext() {
        this.batchError = '';
        if (this.step === 0 && (!this.name || !this.name.trim())) {
            this.dispatchEvent(new CustomEvent('validationerror', { detail: { message: 'Please enter a group name' } }));
            return;
        }
        if (this.step < 3) {
            this.step += 1;
        } else {
            this.dispatchEvent(new CustomEvent('submit', {
                detail: {
                    name: this.name, desc: this.desc, tags: this.tags,
                    rules: this.rules, visibility: this.visibility,
                    bannerUrl: this.bannerUrl,
                    // Audience selection from the shared builder (JSON string for the create payload).
                    audienceData: this.audienceData ? JSON.stringify(this.audienceData) : null
                }
            }));
        }
    }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }
}