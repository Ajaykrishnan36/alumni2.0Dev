import { LightningElement, api } from 'lwc';

export default class SelectedAudiencePanel extends LightningElement {
    @api items = [];

    get hasItems() {
        return Array.isArray(this.items) && this.items.length > 0;
    }

    remove(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('remove', { detail: { id } }));
    }
}