import { LightningElement, api, track } from 'lwc';

export default class KenEventDetailModalV2 extends LightningElement {
    @api event = {};
    @track detailTab = 'about';

    get heroStyle() {
        const g = this.event && this.event.heroGrad ? this.event.heroGrad : 'linear-gradient(135deg,#3061FF,#86E1FF)';
        if (this.event && this.event.image) {
            return `background:linear-gradient(180deg,rgba(0,0,0,0.05) 0%,rgba(0,0,0,0.55) 100%),url('${this.event.image}') center/cover, ${g}`;
        }
        return `background:${g}`;
    }
    get detailTabAbout()        { return this.detailTab === 'about'; }
    get detailTabSchedule()     { return this.detailTab === 'schedule'; }
    get detailTabParticipants() { return this.detailTab === 'participants'; }
    get detailAboutClass()        { return this.detailTabAbout        ? 'dtab dtab--active' : 'dtab'; }
    get detailScheduleClass()     { return this.detailTabSchedule     ? 'dtab dtab--active' : 'dtab'; }
    get detailParticipantsClass() { return this.detailTabParticipants ? 'dtab dtab--active' : 'dtab'; }

    // QA Bug — a completed (past end date) / cancelled / closed event can no longer be
    // registered for. Mirror the same logic kenEventDetailPageV2 uses.
    get isEventClosed() {
        const e = this.event || {};
        const st = (e.eventStatus || '').toLowerCase();
        if (st === 'completed' || st === 'cancelled' || st === 'closed') return true;
        const endRaw = e.endDateRaw || e.endDate;
        if (endRaw) {
            const end = new Date(endRaw);
            if (!isNaN(end.getTime())) {
                const today = new Date(); today.setHours(0, 0, 0, 0);
                if (end.getTime() < today.getTime()) return true;
            }
        }
        return false;
    }
    get registerDisabled() { return this.isEventClosed; }
    get registerLabel() { return this.isEventClosed ? 'Registration Closed' : 'Register Now'; }

    handleDetailTab(e) { this.detailTab = e.currentTarget.dataset.id; }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleRsvp() {
        if (this.isEventClosed) return; // closed events cannot be registered
        this.dispatchEvent(new CustomEvent('rsvp', { detail: { id: this.event.id } }));
    }
    stopBubble(e) { e.stopPropagation(); }
}