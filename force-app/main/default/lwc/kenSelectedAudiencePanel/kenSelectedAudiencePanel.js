import { LightningElement, api, track } from 'lwc';

export default class KenSelectedAudiencePanel extends LightningElement {
    @api items = [];
    @track openMenuId = null;

    get hasItems() {
        return Array.isArray(this.items) && this.items.length > 0;
    }

    get itemsWithState() {
        return (this.items || []).map((item) => ({
            ...item,
            menuOpen: this.openMenuId === item.id
        }));
    }

    toggleMenu(event) {
        const id = event.currentTarget.dataset.id;
        this.openMenuId = this.openMenuId === id ? null : id;
    }

    handleRemoveAction(event) {
        const id = event.currentTarget.dataset.id;
        this.openMenuId = null;
        this.dispatchEvent(new CustomEvent('remove', { detail: { id } }));
    }

    handleCloseMenu() {
        this.openMenuId = null;
    }

    connectedCallback() {
        this._boundKeydown = this._handleKeydown.bind(this);
        document.addEventListener('keydown', this._boundKeydown);
    }

    disconnectedCallback() {
        document.removeEventListener('keydown', this._boundKeydown);
    }

    _handleKeydown(event) {
        if (this.openMenuId && event.key === 'Escape') {
            this.openMenuId = null;
        }
    }
}