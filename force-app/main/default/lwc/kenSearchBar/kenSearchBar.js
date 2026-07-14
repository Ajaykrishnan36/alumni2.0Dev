import { LightningElement, api, track } from 'lwc';

export default class KenSearchBar extends LightningElement {
    @api placeholder = 'Search';
    @api searchValue = '';

    handleInput(event) {
        this.searchValue = event.target.value;
        this.dispatchEvent(new CustomEvent('search', {
            detail: { value: this.searchValue }
        }));
    }
}