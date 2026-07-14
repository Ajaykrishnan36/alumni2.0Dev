import { LightningElement, api } from 'lwc';

export default class KenJobCardV2 extends LightningElement {
    @api recordId;
    @api title;
    @api company;
    @api location;
    @api salary;
    @api skillsMatch = 0;
    @api logoLetter;
    @api logoColor;
    @api tags;
    @api saved = false;
    @api applied = false;
    @api owned = false;

    get logoStyle() {
        const col = this.logoColor || '#3061FF';
        return `background:${col};color:#fff;`;
    }
    get hasLocation() { return !!(this.location && String(this.location).trim().length); }
    get matchClass() {
        const m = Number(this.skillsMatch) || 0;
        return m >= 60 ? 'job__match' : 'job__match job__match--no';
    }
    get isSavedBool()   { return this.saved === true || this.saved === 'true'; }
    get isAppliedBool() { return this.applied === true || this.applied === 'true'; }
    get bookmarkClass() {
        return this.isSavedBool ? 'job__bookmark is-saved' : 'job__bookmark';
    }
    get isOwnedBool()  { return this.owned === true || this.owned === 'true'; }
    get showApply()    { return !this.isOwnedBool; }
    get applyLabel() { return this.isAppliedBool ? 'Applied' : 'Apply'; }
    get applyDisabled() { return this.isAppliedBool; }
    get saveLabel() { return this.isSavedBool ? 'Saved' : 'Save'; }
    get tagItems() {
        const tags = this.tags || [];
        return tags.map((tg, i) => {
            const ic = i === 1 ? '📍 ' : (i === 2 ? '🏢 ' : '');
            return { key: `${this.recordId}-${i}`, label: `${ic}${tg}` };
        });
    }

    handleClick() {
        this.dispatchEvent(new CustomEvent('jobclick', { detail: { id: this.recordId } }));
    }
    handleBookmark(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('bookmark', { detail: { id: this.recordId } }));
    }
    handleApply(event) {
        event.stopPropagation();
        if (this.isAppliedBool) return;
        this.dispatchEvent(new CustomEvent('apply', { detail: { id: this.recordId } }));
    }
    handleSave(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('save', { detail: { id: this.recordId } }));
    }
}