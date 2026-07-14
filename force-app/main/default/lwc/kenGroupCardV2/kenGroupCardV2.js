import { LightningElement, api } from 'lwc';

export default class KenGroupCardV2 extends LightningElement {
    @api recordId;
    @api name;
    @api category;
    @api visibility;
    @api members = 0;
    @api posts = 0;
    @api description;
    @api image;
    @api cover;
    @api joined = false;

    get coverStyle() {
        const c = this.cover || 'linear-gradient(135deg,#3061FF,#9747FF)';
        if (this.image) {
            return `background:linear-gradient(180deg,rgba(0,0,0,0.1) 0%,rgba(0,0,0,0.5) 100%),url('${this.image}') center/cover, ${c}`;
        }
        return `background:${c}`;
    }
    get initial() {
        const n = (this.name || '').trim();
        return n ? n.charAt(0).toUpperCase() : '';
    }
    get statsLabel() {
        const m = Number(this.members) || 0;
        const p = Number(this.posts) || 0;
        return `${m.toLocaleString()} members · ${p} posts`;
    }
    get visClass() {
        return this.visibility === 'Public' ? 'badge badge--public' : 'badge badge--private';
    }
    get joinLabel() { return this.joined ? 'Leave' : 'Join'; }
    get joinClass() { return this.joined ? 'btn btn--outline' : 'btn btn--primary'; }

    handleCardClick() {
        this.dispatchEvent(new CustomEvent('groupclick', { detail: { id: this.recordId } }));
    }
    handleJoinClick(event) {
        event.stopPropagation();
        const name = this.joined ? 'leave' : 'join';
        this.dispatchEvent(new CustomEvent(name, { detail: { id: this.recordId } }));
    }
}