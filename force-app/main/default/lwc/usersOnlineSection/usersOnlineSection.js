import { LightningElement, api, track } from 'lwc';

export default class UsersOnlineSection extends LightningElement {
    @api users = [];

    @track filteredUsers = [];

    connectedCallback() {
        this.filteredUsers = [...this.users];
    }

    get hasUsers() {
        return this.filteredUsers && this.filteredUsers.length > 0;
    }

    handleSearch(event) {
        const searchValue = event.detail.value.toLowerCase();
        if (!searchValue) {
            this.filteredUsers = [...this.users];
            return;
        }

        this.filteredUsers = this.users.filter(user =>
            user.name.toLowerCase().includes(searchValue) ||
            user.batch.toLowerCase().includes(searchValue) ||
            user.profession.toLowerCase().includes(searchValue)
        );
    }
}