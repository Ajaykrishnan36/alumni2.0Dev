import { LightningElement, api } from 'lwc';

export default class KenEventFeaturedCardV2 extends LightningElement {
    @api recordId;
    @api title;
    @api date;
    @api time;
    @api location;
    @api category;
    @api going = 0;
    @api organizer;
    @api image;
    @api heroGrad;
    @api isPast = false;
    @api isMine = false;

    get coverStyle() {
        const g = this.heroGrad || 'linear-gradient(135deg,#3061FF,#86E1FF)';
        const img = (this.image && typeof this.image === 'string') ? this.image.trim() : '';
        if (img && /^(https?:|\/)/.test(img)) {
            return `background:linear-gradient(180deg,rgba(0,0,0,0.05) 0%,rgba(0,0,0,0.55) 100%),url('${img}') center/cover, ${g}`;
        }
        return `background:${g}`;
    }

    get displayCategory() { return this.category || 'Event'; }
    get displayDate()     { return this.date || 'Date TBA'; }
    get displayTime()     { return this.time || ''; }
    get displayLocation() { return this.location || 'Location TBA'; }
    get goingCount()      { return Number(this.going) || 0; }

    handleClick() {
        this.dispatchEvent(new CustomEvent('eventclick', {
            detail: { id: this.recordId }
        }));
    }
}