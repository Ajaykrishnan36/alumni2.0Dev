import { LightningElement, api } from 'lwc';

export default class KenJobDetailModalV2 extends LightningElement {
    @api job = {};
    @api applied = false;
    @api saved = false;

    get coverStyle() {
        const col = (this.job && this.job.col) ? this.job.col : '#3061FF';
        return `background:linear-gradient(135deg, ${col} 0%, ${col}cc 55%, rgba(255,255,255,0.15) 100%), radial-gradient(circle at 80% 20%, rgba(255,255,255,0.18), transparent 60%);color:#fff;`;
    }
    get logoStyle() {
        const col = (this.job && this.job.col) ? this.job.col : '#3061FF';
        return `background:#fff;color:${col};`;
    }
    get logoLetter() {
        return (this.job && this.job.l) ? this.job.l : ((this.job && this.job.company) ? this.job.company.charAt(0) : '?');
    }
    get hasLocation() { return !!(this.job && this.job.location && String(this.job.location).trim().length); }
    get matchClass() {
        const m = this.job && this.job.skillsMatch ? this.job.skillsMatch : 0;
        return m >= 60 ? 'job__match' : 'job__match job__match--no';
    }
    get applyLabel() { return this.applied ? 'Applied' : 'Apply'; }
    get applyDisabled() { return this.applied; }
    // Hide the Apply CTA on a job the current user posted (can't apply to your own job).
    get isOwnedByMe() { return !!(this.job && this.job.isOwnedByMe); }
    get showApply() { return !this.isOwnedByMe; }
    get saveLabel() { return this.saved ? 'Saved' : 'Save'; }
    get tagItems() {
        const tags = (this.job && this.job.tags) || [];
        return tags.map((tg, i) => ({ key: `${this.job.id}-${i}`, label: tg }));
    }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleApply() {
        if (this.applied) return;
        this.dispatchEvent(new CustomEvent('apply', { detail: { id: this.job.id } }));
    }
    handleSave() {
        this.dispatchEvent(new CustomEvent('save', { detail: { id: this.job.id } }));
    }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }
    stopBubble(e) { e.stopPropagation(); }
}