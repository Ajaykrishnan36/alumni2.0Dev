import { LightningElement, api, track } from 'lwc';

export default class KenSearchableSelect extends LightningElement {
    @api placeholder = 'Select';
    @api noResultsText = 'No results found';

    @track isOpen = false;
    @track searchText = '';

    _options = [];
    _value = '';
    _boundDocumentClick;

    @api
    get options() {
        return this._options;
    }
    set options(value) {
        this._options = Array.isArray(value) ? value : [];
        this.syncSearchTextWithValue();
    }

    @api
    get value() {
        return this._value;
    }
    set value(newValue) {
        this._value = newValue || '';
        this.syncSearchTextWithValue();
    }

    connectedCallback() {
        this._boundDocumentClick = this.handleDocumentClick.bind(this);
        document.addEventListener('click', this._boundDocumentClick);
    }

    disconnectedCallback() {
        if (this._boundDocumentClick) {
            document.removeEventListener('click', this._boundDocumentClick);
        }
    }

    get filteredOptions() {
        const term = (this.searchText || '').trim().toLowerCase();
        if (!term) {
            return this._options;
        }
        return this._options.filter((option) => (option.label || '').toLowerCase().includes(term));
    }

    get hasFilteredOptions() {
        return this.filteredOptions.length > 0;
    }

    get computedWrapperClass() {
        return this.isOpen ? 'searchable-select is-open' : 'searchable-select';
    }

    handleContainerClick(event) {
        event.stopPropagation();
    }

    handleInputFocus(event) {
        event.stopPropagation();
        this.isOpen = true;
    }

    handleInputClick(event) {
        event.stopPropagation();
        this.isOpen = true;
    }

    handleInputChange(event) {
        this.searchText = event.target.value || '';
        this.isOpen = true;
    }

    handleToggleClick(event) {
        event.stopPropagation();
        this.isOpen = !this.isOpen;
        if (!this.isOpen) {
            this.syncSearchTextWithValue();
        }
    }

    handleOptionMouseDown(event) {
        event.preventDefault();
        event.stopPropagation();
        const selectedValue = event.currentTarget.dataset.value || '';
        this.selectValue(selectedValue);
    }

    handleClearClick(event) {
        event.stopPropagation();
        this.selectValue('');
    }

    handleDocumentClick() {
        if (this.isOpen) {
            this.isOpen = false;
            this.syncSearchTextWithValue();
        }
    }

    selectValue(selectedValue) {
        this._value = selectedValue;
        this.syncSearchTextWithValue();
        this.isOpen = false;
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: this._value }
            })
        );
    }

    syncSearchTextWithValue() {
        if (!this._value) {
            this.searchText = '';
            return;
        }
        const selectedOption = this._options.find((option) => option.value === this._value);
        // Fallback to raw value if options haven't loaded yet (value set before options during re-mount)
        this.searchText = selectedOption ? selectedOption.label : this._value;
    }
}