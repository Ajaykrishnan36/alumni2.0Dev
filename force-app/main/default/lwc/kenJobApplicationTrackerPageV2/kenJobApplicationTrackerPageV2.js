import { LightningElement, api } from 'lwc';

export default class KenJobApplicationTrackerPageV2 extends LightningElement {
    @api job = {};

    // ---------- HEADER ----------
    get logoLetter() {
        return (this.job && this.job.l) ? this.job.l : ((this.job && this.job.company) ? this.job.company.charAt(0) : '?');
    }
    get logoStyle() {
        const col = (this.job && this.job.col) ? this.job.col : '#3061FF';
        return `background:${col};color:#fff;`;
    }
    get tagItems() {
        const tags = (this.job && this.job.tags) || [];
        return tags.map((t, i) => ({ key: `${this.job.id}-tag-${i}`, label: t }));
    }
    get matchPercent() {
        if (this.job && this.job.matchPercent) return this.job.matchPercent;
        if (this.job && typeof this.job.skillsMatch === 'number') return `${this.job.skillsMatch}%`;
        return '';
    }
    get hasMatch() { return !!this.matchPercent; }
    get appliedStatus() { return (this.job && this.job.appliedStatus) ? this.job.appliedStatus : ''; }
    get hasAppliedStatus() { return !!this.appliedStatus; }
    get appliedStatusClass() {
        const s = (this.appliedStatus || '').toLowerCase();
        if (s === 'offered')     return 'status-badge status-badge--success';
        if (s === 'rejected')    return 'status-badge status-badge--danger';
        if (s === 'shortlisted') return 'status-badge status-badge--info';
        return 'status-badge status-badge--neutral';
    }

    // ---------- STEPPER ----------
    get steps() {
        const raw = (this.job && Array.isArray(this.job.applicationSteps)) ? this.job.applicationSteps : [];
        return raw.map((s, i) => {
            const state = s.state || 'upcoming';
            return {
                ...s,
                key: s.id || `st-${i}`,
                indexLabel: i + 1,
                isCompleted: state === 'completed',
                isActive:    state === 'active',
                isRejected:  state === 'rejected',
                isUpcoming:  state === 'upcoming',
                cssClass: `step step--${state}`,
                connectorClass: state === 'completed' ? 'step-connector step-connector--done' : 'step-connector'
            };
        });
    }
    get hasSteps() { return this.steps.length > 0; }

    // ---------- STATE PANELS ----------
    get applicationState() { return (this.job && this.job.applicationState) ? this.job.applicationState : 'none'; }
    get isActionRequired() { return this.applicationState === 'actionRequired'; }
    get isOffered()        { return this.applicationState === 'offered'; }
    get isRejected()       { return this.applicationState === 'rejected'; }
    get isSlotClosed()     { return this.applicationState === 'slotClosed'; }
    get isInProgress()     { return this.applicationState === 'inProgress'; }
    get hasStatePanel() {
        return this.isActionRequired || this.isOffered || this.isRejected || this.isSlotClosed || this.isInProgress;
    }

    get nextAction() { return (this.job && this.job.nextAction) ? this.job.nextAction : null; }
    get hasNextAction() { return !!this.nextAction; }
    get nextActionTitle()    { return this.nextAction ? this.nextAction.title    : 'Action required'; }
    get nextActionDeadline() { return this.nextAction ? this.nextAction.deadline : ''; }
    get nextActionCta()      { return this.nextAction ? this.nextAction.cta      : 'Book Slot'; }

    get offer() { return (this.job && this.job.offer) ? this.job.offer : null; }
    get hasOffer() { return !!this.offer; }

    // ---------- HANDLERS ----------
    handleBack()      { this.dispatchEvent(new CustomEvent('back')); }
    handleApply()     { this.dispatchEvent(new CustomEvent('apply', { detail: { id: this.job ? this.job.id : null } })); }
    handleBookSlot()  { this.dispatchEvent(new CustomEvent('bookslot', { detail: { id: this.job ? this.job.id : null } })); }
    handleCompare()   {
        this.dispatchEvent(new CustomEvent('viewoffers', { detail: { jobIds: [this.job ? this.job.id : null].filter(Boolean) } }));
    }
    handleAccept()    { this.dispatchEvent(new CustomEvent('accept', { detail: { id: this.job ? this.job.id : null } })); }
    handleDecline()   { this.dispatchEvent(new CustomEvent('decline', { detail: { id: this.job ? this.job.id : null } })); }
}