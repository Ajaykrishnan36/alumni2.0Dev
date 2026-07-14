import { LightningElement, api } from 'lwc';

const CATEGORIES = ['All', 'Batch', 'Sports', 'Interest', 'Founders', 'Regional'];

export default class KenGroupsFilterBarV2 extends LightningElement {
    @api activeCategory = 'All';

    get chips() {
        return CATEGORIES.map(c => ({
            id: c,
            label: c,
            cssClass: c === this.activeCategory ? 'chip chip--active' : 'chip'
        }));
    }

    handleSearch(event) {
        this.dispatchEvent(new CustomEvent('search', { detail: { value: event.target.value } }));
    }
    handleCategory(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('categorychange', { detail: { id } }));
    }
}