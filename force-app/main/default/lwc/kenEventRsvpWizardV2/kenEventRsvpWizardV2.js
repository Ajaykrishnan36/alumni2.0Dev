import { LightningElement, api, track } from 'lwc';

const RSVP_LABELS = ['Participants', 'Select Sessions', 'Summary', 'Success'];
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export default class KenEventRsvpWizardV2 extends LightningElement {
    @api eventId;
    @api eventTitle = '';
    @track currentStep = 1;
    @track whoTab = 'myself';

    // Actual participant rows the user enters. Starts with one row.
    @track participants = [{ key: 'p-0', name: '', email: '', nameError: '', emailError: '' }];
    @track formError = '';
    _seq = 1;

    get rsvpStep1() { return this.currentStep === 1; }
    get rsvpStep2() { return this.currentStep === 2; }
    get rsvpStep3() { return this.currentStep === 3; }
    get rsvpStep4() { return this.currentStep === 4; }

    get isBulk() { return this.whoTab === 'bulk'; }

    get progressStyle() {
        const pct = Math.min(100, (this.currentStep / 3) * 100);
        return `width:${pct}%`;
    }

    get stepLabel() {
        const label = RSVP_LABELS[this.currentStep - 1] || '';
        const num = this.currentStep > 3 ? 3 : this.currentStep;
        return `STEP ${num} OF 3 — ${label}`;
    }

    get whoTabMyselfClass() { return this.whoTab === 'myself' ? 'who-tab who-tab--active' : 'who-tab'; }
    get whoTabBulkClass()   { return this.whoTab === 'bulk'   ? 'who-tab who-tab--active' : 'who-tab'; }

    get backDisabled() { return this.currentStep <= 1; }
    get showNext() { return this.currentStep < 3; }
    get showSubmit() { return this.currentStep === 3; }
    get hideFooter() { return this.currentStep === 4; }

    // ----- Summary derived from ACTUAL participants (no hardcoded count) -----
    get validParticipants() {
        return this.participants.filter(p => p.name.trim());
    }
    get participantCount() { return this.validParticipants.length; }
    get summaryParticipants() {
        return this.validParticipants.map((p, i) => ({
            key: p.key,
            name: p.name.trim(),
            email: p.email.trim() || '—',
            label: `${i + 1}. ${p.name.trim()}`
        }));
    }
    get canRemoveParticipant() { return this.participants.length > 1; }

    get stepper() {
        return [
            { id: 1, label: 'Participants',    cls: this._stepCls(1), num: this.currentStep > 1 ? '✓' : '1' },
            { id: 2, label: 'Select Sessions', cls: this._stepCls(2), num: this.currentStep > 2 ? '✓' : '2' },
            { id: 3, label: 'Summary',         cls: this._stepCls(3), num: '3' }
        ];
    }
    _stepCls(n) {
        if (this.currentStep > n) return 'step step--done';
        if (this.currentStep === n) return 'step step--active';
        return 'step';
    }

    handleWhoTab(e) {
        this.whoTab = e.currentTarget.dataset.id;
        // Myself = single participant row; Bulk = keep/allow multiple.
        if (this.whoTab === 'myself') {
            this.participants = [this.participants[0] || this._newRow()];
        }
        this.formError = '';
    }

    _newRow() {
        const row = { key: `p-${this._seq++}`, name: '', email: '', nameError: '', emailError: '' };
        return row;
    }

    handleAddParticipant() {
        this.participants = [...this.participants, this._newRow()];
    }
    handleRemoveParticipant(e) {
        const key = e.currentTarget.dataset.key;
        if (this.participants.length <= 1) return;
        this.participants = this.participants.filter(p => p.key !== key);
    }
    handleNameInput(e) {
        const key = e.currentTarget.dataset.key;
        const val = e.target.value;
        this.participants = this.participants.map(p =>
            p.key === key ? { ...p, name: val, nameError: '' } : p);
        this.formError = '';
    }
    handleEmailInput(e) {
        const key = e.currentTarget.dataset.key;
        const val = e.target.value;
        this.participants = this.participants.map(p =>
            p.key === key ? { ...p, email: val, emailError: '' } : p);
        this.formError = '';
    }

    // Validate every participant row: required name + valid email. At least one participant.
    _validateParticipants() {
        let ok = true;
        const rows = this.participants.map(p => {
            const name = p.name.trim();
            const email = p.email.trim();
            let nameError = '';
            let emailError = '';
            if (!name) { nameError = 'Name is required'; ok = false; }
            if (!email) { emailError = 'Email is required'; ok = false; }
            else if (!EMAIL_RE.test(email)) { emailError = 'Enter a valid email'; ok = false; }
            return { ...p, nameError, emailError };
        });
        this.participants = rows;
        if (!rows.some(p => p.name.trim())) {
            ok = false;
            this.formError = 'Add at least one participant.';
        } else if (!ok) {
            this.formError = 'Please fix the highlighted fields before continuing.';
        } else {
            this.formError = '';
        }
        return ok;
    }

    handleNext() {
        if (this.currentStep === 1 && !this._validateParticipants()) return;
        if (this.currentStep < 3) this.currentStep += 1;
    }
    handleBack() {
        this.formError = '';
        if (this.currentStep > 1) this.currentStep -= 1;
    }
    handleSubmit() {
        // No payment — confirm registration directly.
        this.currentStep = 4;
        this.dispatchEvent(new CustomEvent('submit', {
            detail: {
                eventId: this.eventId,
                participants: this.validParticipants.map(p => ({ name: p.name.trim(), email: p.email.trim() }))
            }
        }));
    }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    stopBubble(e) { e.stopPropagation(); }
}