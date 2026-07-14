import { LightningElement, api } from 'lwc';

export default class KenGroupMemberAvatarV2 extends LightningElement {
    @api member;
    @api showOnlineDot = false;

    get initial() { return this.member && this.member.initial ? this.member.initial : (this.member && this.member.name ? this.member.name.charAt(0) : '?'); }
    get name() { return this.member ? this.member.name : ''; }
    get batch() { return this.member ? this.member.batch : ''; }
    get avatarStyle() {
        if (!this.member) return '';
        if (this.member.avatarStyle) return this.member.avatarStyle;
        if (this.member.color) return `background:${this.member.color}`;
        return 'background:linear-gradient(135deg,#E8B4D6,#B033C8)';
    }
    get isOnline() { return !!(this.member && this.member.online); }
    get showDot() { return this.showOnlineDot && this.isOnline; }
}