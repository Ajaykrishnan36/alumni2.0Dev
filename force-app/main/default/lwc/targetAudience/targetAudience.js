import { LightningElement, api } from 'lwc';

export default class TargetAudience extends LightningElement {
    @api selectedSuitableFor = [];
    @api selectedLanguages = [];
    @api suitableForOptions = [];
    @api languageOptions = [];
    @api showSuitableForDropdown = false;
    @api showLanguageDropdown = false;
    @api isPicklistDataLoaded = false;
    @api validationErrors = {};

    handleSuitableForDropdownToggle(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('suitablefortoggle', {
            bubbles: true,
            composed: true
        }));
    }

    handleSuitableForSelect(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value;
        this.dispatchEvent(new CustomEvent('suitableforselect', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }

    handleRemoveSuitableFor(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value;
        this.dispatchEvent(new CustomEvent('removesuitablefor', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }

    handleLanguageDropdownToggle(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('languagetoggle', {
            bubbles: true,
            composed: true
        }));
    }

    handleLanguageSelect(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value;
        this.dispatchEvent(new CustomEvent('languageselect', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }

    handleRemoveLanguage(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value;
        this.dispatchEvent(new CustomEvent('removelanguage', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }

    handleDropdownContainerClick(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('dropdownclick', {
            detail: { field: event.currentTarget.dataset.field },
            bubbles: true,
            composed: true
        }));
    }
}