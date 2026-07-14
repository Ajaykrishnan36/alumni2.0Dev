import { LightningElement, api } from 'lwc';

export default class GroupsJoined extends LightningElement {
    @api groups = [];

    get hasGroups() {
        return this.groups && this.groups.length > 0;
    }

    handleDiscover() {
        // Dispatch event or navigate
    }
}