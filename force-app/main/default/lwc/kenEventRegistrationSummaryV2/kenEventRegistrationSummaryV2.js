import { LightningElement, api } from 'lwc';

export default class KenEventRegistrationSummaryV2 extends LightningElement {
    @api registration;
    @api event;

    get eventTitle() { return this.event ? this.event.title : ''; }
    get eventMeta() {
        if (!this.event) return '';
        const parts = [this.event.date, this.event.loc, this.event.time].filter(Boolean);
        return parts.join('  ·  ');
    }
    get hasRegistration() { return !!this.registration; }
    get participants() {
        return ((this.registration && this.registration.participants) || []).map((p, i) => ({
            ...p,
            key: p.id || `pt-${i}`
        }));
    }
    get registeredSessions() {
        return ((this.registration && this.registration.registeredSessions) || []).map((s, i) => ({
            ...s,
            key: s.id || `rs-${i}`
        }));
    }
    get hasParticipants() { return this.participants.length > 0; }
    get hasSessions()     { return this.registeredSessions.length > 0; }

    handleBack() { this.dispatchEvent(new CustomEvent('back')); }
    handleCancelRegistration() { this.dispatchEvent(new CustomEvent('cancelregistration')); }
}