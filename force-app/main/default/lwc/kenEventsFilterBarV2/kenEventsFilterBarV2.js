import { LightningElement, api } from 'lwc';

// Fallback chip set used only if the parent doesn't pass real categories.
const FALLBACK_CATEGORIES = ['All', 'Reunion', 'Webinar', 'Workshop', 'Fundraiser', 'Networking', 'Cultural'];

export default class KenEventsFilterBarV2 extends LightningElement {
    @api activeCategory = 'All';
    // Parent passes the REAL distinct categories present in the data (without 'All').
    // We always prepend 'All'. Falls back to the static set when none provided.
    @api categoryOptions;

    get categories() {
        const list = Array.isArray(this.categoryOptions) && this.categoryOptions.length
            ? ['All', ...this.categoryOptions.filter(c => c && c !== 'All')]
            : FALLBACK_CATEGORIES;
        return list.map(c => ({
            id: c,
            label: c,
            chipClass: c === this.activeCategory ? 'chip chip--active' : 'chip'
        }));
    }

    handleCat(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('categorychange', { detail: { id } }));
    }

    handleSearch(event) {
        const term = event.target.value;
        this.dispatchEvent(new CustomEvent('search', { detail: { term } }));
    }
}