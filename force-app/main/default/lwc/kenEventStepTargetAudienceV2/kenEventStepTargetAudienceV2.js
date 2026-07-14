import { LightningElement, api } from 'lwc';
import createContentVersion from '@salesforce/apex/KenCreateContentVersion.createContentVersion';

// Valid values must match the restricted Ken_Event_Master__c.Language__c picklist.
const LANGUAGE_OPTIONS = ['English', 'Hindi', 'French'];

export default class KenEventStepTargetAudienceV2 extends LightningElement {
    @api eventTitle = '';
    @api category = '';
    @api eventType = 'In-Person';
    @api language = 'English';   // multiselect picklist value(s), ';'-separated
    @api description = '';
    @api hostType = 'Offline';
    @api location = '';
    @api meetingLink = '';
    @api speakerDetails = '';
    @api whatToExpect = '';
    @api agenda = '';
    // QA Bug — cover photo (stored to Ken_Event_Master__c.Event_banner__c as a data URI).
    @api imageUrl = '';
    @api imageName = '';

    // QA Bug — raised to 2 MB. The image is uploaded as a ContentVersion (returns a public
    // URL stored in Event_banner__c), NOT a base64 data URI — so it's no longer bound by the
    // LongTextArea 128KB limit and supports full-size cover photos.
    MAX_COVER_BYTES = 2 * 1024 * 1024;
    @api coverError = '';
    @api coverUploading = false;

    get hasCover() { return !!(this.imageUrl && this.imageUrl.length); }
    get coverLabel() {
        if (this.coverUploading) return 'Uploading…';
        return this.imageName ? this.imageName : 'Upload cover photo';
    }
    get coverPreviewStyle() {
        const box = 'width:120px;height:72px;border-radius:8px;border:1px solid #e5e7eb;flex:0 0 auto;';
        return this.hasCover
            ? `${box}background-image:url('${this.imageUrl}');background-size:cover;background-position:center;`
            : box;
    }

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
            // Upload to a ContentVersion + public distribution → returns a usable URL.
            createContentVersion({ title: 'EventCover_' + Date.now() + '_' + fileName, base64String: base64 })
                .then(url => {
                    this.coverUploading = false;
                    if (url && /^https?:\/\//i.test(url)) {
                        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'imageUrl', value: url } }));
                        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'imageName', value: fileName } }));
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
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'imageUrl', value: '' } }));
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'imageName', value: '' } }));
    }

    get isOnline() { return this.hostType === 'Online'; }
    get isOffline() { return this.hostType === 'Offline'; }
    get onlineClass() { return 'seg-btn' + (this.hostType === 'Online' ? ' seg-btn--on' : ''); }
    get offlineClass() { return 'seg-btn' + (this.hostType === 'Offline' ? ' seg-btn--on' : ''); }

    // --- Language multi-select ---
    get _selectedLanguages() {
        return String(this.language || '').split(';').map(s => s.trim()).filter(Boolean);
    }
    get languageOptions() {
        const sel = new Set(this._selectedLanguages);
        return LANGUAGE_OPTIONS.map(v => ({ value: v, label: v, checked: sel.has(v) }));
    }

    handleInput(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.target.value;
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field, value }
        }));
    }

    handleHostType(event) {
        const value = event.currentTarget.dataset.val;
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: 'hostType', value }
        }));
    }

    handleLanguageToggle(event) {
        const val = event.currentTarget.dataset.val;
        const sel = this._selectedLanguages;
        const idx = sel.indexOf(val);
        if (idx >= 0) sel.splice(idx, 1); else sel.push(val);
        // Preserve picklist order for a clean stored value.
        const ordered = LANGUAGE_OPTIONS.filter(v => sel.indexOf(v) >= 0);
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: 'language', value: ordered.join(';') }
        }));
    }
}