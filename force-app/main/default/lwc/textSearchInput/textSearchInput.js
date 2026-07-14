/**
 * Thin wrapper around lightning-input(type="search").
 * Exists mainly to satisfy the dependency in targetAudienceSelection
 * and keep the screen modular.
 */
import { LightningElement, api } from 'lwc';

export default class TextSearchInput extends LightningElement {
    @api label;
    @api placeholder = 'Search and select';
    @api value = '';
    @api disabled = false;

    handleChange(event) {
        this.value = event.target.value;
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: this.value }
            })
        );
    }
}