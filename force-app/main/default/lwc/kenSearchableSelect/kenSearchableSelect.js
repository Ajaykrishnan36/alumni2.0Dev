import { LightningElement, api, track } from 'lwc';

const OPEN_EVENT_NAME = 'kensearchableselect_open';

export default class KenSearchableSelect extends LightningElement {
    @api placeholder = 'Select';
    @api noResultsText = 'No results found';

    @track isOpen = false;
    @track searchText = '';

    _options = [];
    _value = '';
    _boundDocumentClick;
    _boundOtherInstanceOpened;
    _justFocused = false;
    _instanceId = `kss-${Date.now()}-${Math.random().toString(36).slice(2)}`;

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
        // A regular 'click' listener can't tell us when a DIFFERENT dropdown
        // opened — each instance stops its own click from bubbling to the
        // document (see handleContainerClick), so this instance never sees
        // that click at all. Instead, every instance broadcasts a custom event
        // on open, and every other instance closes itself in response.
        this._boundOtherInstanceOpened = this.handleOtherInstanceOpened.bind(this);
        document.addEventListener(OPEN_EVENT_NAME, this._boundOtherInstanceOpened);
    }

    disconnectedCallback() {
        if (this._boundDocumentClick) {
            document.removeEventListener('click', this._boundDocumentClick);
        }
        if (this._boundOtherInstanceOpened) {
            document.removeEventListener(OPEN_EVENT_NAME, this._boundOtherInstanceOpened);
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
        this._justFocused = true;
        this.openDropdown();
    }

    handleInputClick(event) {
        event.stopPropagation();
        // Focus fires just before click when the box wasn't already focused —
        // skip the toggle then (focus already opened it) so a single click
        // doesn't open and immediately close it. A click on an already-focused
        // box (no preceding focus event) toggles open/closed.
        if (this._justFocused) {
            this._justFocused = false;
            return;
        }
        if (this.isOpen) {
            this.closeDropdown();
        } else {
            this.openDropdown();
        }
    }

    handleInputChange(event) {
        this.searchText = event.target.value || '';
        this.openDropdown();
    }

    handleToggleClick(event) {
        event.stopPropagation();
        if (this.isOpen) {
            this.closeDropdown();
        } else {
            this.openDropdown();
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
        this.closeDropdown();
    }

    // Another kenSearchableSelect instance just opened — close this one if it
    // was open, so only one dropdown is ever expanded at a time.
    handleOtherInstanceOpened(event) {
        if (event.detail?.sourceId === this._instanceId) {
            return;
        }
        this.closeDropdown();
    }

    openDropdown() {
        if (this.isOpen) {
            return;
        }
        this.isOpen = true;
        document.dispatchEvent(
            new CustomEvent(OPEN_EVENT_NAME, { detail: { sourceId: this._instanceId } })
        );
    }

    closeDropdown() {
        if (!this.isOpen) {
            return;
        }
        this.isOpen = false;
        this.syncSearchTextWithValue();
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