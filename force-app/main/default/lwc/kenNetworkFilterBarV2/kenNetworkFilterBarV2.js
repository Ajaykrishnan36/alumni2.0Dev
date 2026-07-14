import { LightningElement, api } from 'lwc';

export default class KenNetworkFilterBarV2 extends LightningElement {
    // Pre-fill from the global topbar search (?q=...) so the box reflects the active query.
    @api searchValue = '';

    handleSearch(event) {
        this.dispatchEvent(new CustomEvent('search', { detail: { value: event.target.value } }));
    }
    handleSort(event) {
        this.dispatchEvent(new CustomEvent('sort', { detail: { value: event.target.value } }));
    }
    handleFilter() {
        this.dispatchEvent(new CustomEvent('filter'));
    }
}