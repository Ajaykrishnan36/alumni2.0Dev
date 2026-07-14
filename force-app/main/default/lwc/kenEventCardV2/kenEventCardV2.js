import { LightningElement, api } from 'lwc';

export default class KenEventCardV2 extends LightningElement {
    @api recordId;
    @api title;
    @api date;
    @api time;
    @api location;
    @api category;
    @api going = 0;
    @api organizer;
    @api status;
    @api image;
    @api heroGrad;
    @api isPast = false;
    @api isMine = false;
    // Live status for Online events (computed in the parent's mapEventList).
    @api isHappeningNow = false;
    @api showJoinNow = false;
    @api meetingLink;

    get isPastBool() { return this.isPast === true || this.isPast === 'true'; }
    get isMineBool() { return this.isMine === true || this.isMine === 'true'; }
    get isHappeningNowBool() { return this.isHappeningNow === true || this.isHappeningNow === 'true'; }
    get showJoinNowBool() { return this.showJoinNow === true || this.showJoinNow === 'true'; }

    get coverStyle() {
        const g = this.heroGrad || 'linear-gradient(135deg,#F59E0B 0%,#FCD34D 100%)';
        // Validate image URL — fall back to gradient if missing or obviously not a URL.
        const img = (this.image && typeof this.image === 'string') ? this.image.trim() : '';
        if (img && /^(https?:|\/|data:image)/.test(img)) {
            return `background:linear-gradient(180deg,rgba(0,0,0,0.05) 0%,rgba(0,0,0,0.45) 100%),url('${img}') center/cover, ${g}`;
        }
        return `background:${g}`;
    }

    get badgeLabel() {
        if (this.isPastBool) return 'Completed';
        if (this.isMineBool) return this.status || 'Registered';
        return this.category || 'Event';
    }

    get catClass() {
        return this.isPastBool ? 'upcard__cat upcard__cat--past' : 'upcard__cat';
    }

    get displayDate()     { return this.date || 'Date TBA'; }
    get displayLocation() { return this.location || 'Location TBA'; }

    handleClick() {
        this.dispatchEvent(new CustomEvent('eventclick', { detail: { id: this.recordId } }));
    }

    handleJoin(event) {
        // Don't let the Join click bubble to the card (which opens the detail view).
        event.stopPropagation();
        if (this.meetingLink) {
            try { window.open(this.meetingLink, '_blank', 'noopener'); }
            catch (e) { window.location.assign(this.meetingLink); }
        }
    }
}