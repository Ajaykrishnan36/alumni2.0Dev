import { LightningElement, api } from 'lwc';

export default class KenChatThreadListV2 extends LightningElement {
    static renderMode = 'light';
    @api threads = [];
    @api searchQ = '';

    handleSearch(event) {
        this.dispatchEvent(new CustomEvent('search', {
            detail: { value: event.target.value },
            bubbles: true,
            composed: true
        }));
    }
    handleSelect(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('selectthread', {
            detail: { id },
            bubbles: true,
            composed: true
        }));
    }
    handleNewChat() {
        this.dispatchEvent(new CustomEvent('newchat', { bubbles: true, composed: true }));
    }
}