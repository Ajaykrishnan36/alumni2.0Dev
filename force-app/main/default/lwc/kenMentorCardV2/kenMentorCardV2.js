import { LightningElement, api } from 'lwc';

export default class KenMentorCardV2 extends LightningElement {
    @api recordId;
    @api name;
    @api title;
    @api company;
    @api location;
    @api expertise;
    @api batch;
    @api photoUrl;
    @api willing = false;
    @api sessionCount = 0;
    @api rating;
    @api initial;
    @api avatarColor;
    @api tag;
    @api role = '';

    get avatarStyle() {
        return `background:${this.avatarColor || '#EAEFFF'}`;
    }
    get tagStyle() {
        return this.tag === 'Mentor' ? 'background:#19A974' : 'background:#3061FF';
    }
    get displayInitial() {
        if (this.initial) return this.initial;
        const n = (this.name || '').trim();
        return n ? n.charAt(0).toUpperCase() : '';
    }

    handleClick() {
        this.dispatchEvent(new CustomEvent('mentorclick', { detail: { id: this.recordId } }));
    }
    handleBook(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('book', { detail: { id: this.recordId } }));
    }
    handleMessage(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('message', { detail: { id: this.recordId } }));
    }
}