import { LightningElement, api, track } from 'lwc';

export default class KenNetworkListMobile extends LightningElement {
    @api alumni = [];
    @api activeTabLabel = 'All Alumni';
    @api showBatch = false;
    @track isSortOpen = false;

    get isCompact() {
        return true;
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    handleSearch(event) {
        this.dispatchEvent(new CustomEvent('search', { detail: event.detail }));
    }

    handleSortToggle(event) {
        event.stopPropagation();
        this.isSortOpen = !this.isSortOpen;
        if (this.isSortOpen) {
            setTimeout(() => {
                const handler = () => {
                    this.isSortOpen = false;
                    document.removeEventListener('click', handler);
                };
                document.addEventListener('click', handler);
            }, 0);
        }
    }

    handleSortSelect(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value || 'clear';
        this.isSortOpen = false;
        this.dispatchEvent(new CustomEvent('sortchange', { detail: value === 'clear' ? '' : value }));
    }

    handleSortClick() {
        this.dispatchEvent(new CustomEvent('sortclick'));
    }

    handleFiltersClick() {
        this.dispatchEvent(new CustomEvent('filtersclick'));
    }

    handleProfileClick(event) {
        this.dispatchEvent(new CustomEvent('profileclick', { detail: event.detail }));
    }
}