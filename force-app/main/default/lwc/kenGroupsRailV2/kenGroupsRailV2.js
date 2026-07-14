import { LightningElement, api } from 'lwc';

export default class KenGroupsRailV2 extends LightningElement {
    @api joinedGroups = [];
    @api createdGroups = [];

    get joinedDecorated() {
        return (this.joinedGroups || []).map(g => this._decorate(g));
    }
    get createdDecorated() {
        return (this.createdGroups || []).map(g => this._decorate(g));
    }
    get joinedCount() { return (this.joinedGroups || []).length; }
    get createdCount() { return (this.createdGroups || []).length; }
    get hasJoined() { return this.joinedCount > 0; }
    get hasCreated() { return this.createdCount > 0; }
    get createdTitle() { return `Created Groups (${this.createdCount})`; }

    _decorate(g) {
        return {
            ...g,
            coverStyle: `background:${g.cover}`,
            membersLabel: `${g.members.toLocaleString()} members`,
            visClass: g.visibility === 'Public' ? 'side-row__tag side-row__tag--public' : 'side-row__tag'
        };
    }

    handleViewAll() {
        this.dispatchEvent(new CustomEvent('viewall'));
    }
    handleDiscover() {
        this.dispatchEvent(new CustomEvent('discover'));
    }
    handleCreate() {
        this.dispatchEvent(new CustomEvent('creategroup'));
    }
    handleRowClick(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('groupclick', { detail: { id } }));
    }
}