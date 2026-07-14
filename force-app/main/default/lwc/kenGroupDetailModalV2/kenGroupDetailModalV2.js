import { LightningElement, api, track } from 'lwc';

const TABS = [
    { id: 'about', label: 'About' },
    { id: 'feed', label: 'Feed' },
    { id: 'events', label: 'Events' },
    { id: 'members', label: 'Members' }
];

export default class KenGroupDetailModalV2 extends LightningElement {
    @api group;
    @api joined = false;
    @api feed = [];
    @api events = [];
    @api members = [];

    @track activeTab = 'about';

    get tabs() {
        return TABS.map(t => ({ ...t, cssClass: t.id === this.activeTab ? 'tab tab--active' : 'tab' }));
    }
    get isAbout() { return this.activeTab === 'about'; }
    get isFeed() { return this.activeTab === 'feed'; }
    get isEvents() { return this.activeTab === 'events'; }
    get isMembers() { return this.activeTab === 'members'; }

    get decoratedGroup() {
        if (!this.group) return null;
        return {
            ...this.group,
            coverStyle: `background:${this.group.cover}`,
            initial: (this.group.name || '?').charAt(0).toUpperCase(),
            membersLabel: `${this.group.members.toLocaleString()} members`,
            joinLabel: this.joined ? 'Leave Group' : 'Join Group',
            joinClass: this.joined ? 'btn btn--outline' : 'btn btn--primary',
            metaLine: `${this.group.category} · ${this.group.visibility} · ${this.group.members.toLocaleString()} members`,
            rulesList: (this.group.rules || []).map((r, i) => ({ id: i, text: r }))
        };
    }

    get feedDecorated() {
        return (this.feed || []).map(u => ({
            ...u,
            initial: u.author.charAt(0),
            tagsJoined: u.tags ? u.tags.join(' ') : '',
            commentsLabel: `${u.comments} comments`
        }));
    }
    get eventsDecorated() {
        return (this.events || []).map(e => ({ ...e, coverStyle: `background:${e.cover}` }));
    }
    get membersDecorated() {
        return (this.members || []).map(m => ({ ...m, avatarStyle: `background:${m.color}` }));
    }

    handleTab(event) {
        this.activeTab = event.currentTarget.dataset.id;
    }
    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
    handleBackdrop(event) {
        if (event.target.classList && event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }
    handleJoin() {
        const name = this.joined ? 'leave' : 'join';
        this.dispatchEvent(new CustomEvent(name, { detail: { id: this.group ? this.group.id : null } }));
    }
}