import { LightningElement, api, track } from 'lwc';

/**
 * Flag-picker-style searchable picklist used on the registration screen.
 *
 * Modelled on kenCustomPhoneInput's country dropdown: a trigger row that shows
 * the selected label (or placeholder) and opens a fixed-positioned dropdown with
 * a dedicated search box at the top and a scrollable, filterable option list.
 *
 * Fixed positioning (computed from getBoundingClientRect on open/scroll/resize)
 * lets the dropdown escape any overflow/stacking-context clipping — the limitation
 * of the shared c-ken-searchable-select used elsewhere.
 *
 * Public API mirrors c-ken-searchable-select so it is a drop-in replacement:
 *   options : Array<{ label, value }>
 *   value   : current value (string)
 *   change  : CustomEvent with detail.value
 */
export default class KenSearchablePicklist extends LightningElement {
    @api placeholder = 'Select';
    @api searchPlaceholder = 'Search...';
    @api noResultsText = 'No results found';
    @api disabled = false;

    @track isOpen = false;
    @track searchText = '';
    @track activeIndex = -1;
    @track spError = '';

    _options = [];
    _value = '';
    _customValidity = '';
    _boundReposition;
    _scrollActiveIntoView = false;

    @api
    get options() {
        return this._options;
    }
    set options(value) {
        this._options = Array.isArray(value) ? value : [];
    }

    @api
    get value() {
        return this._value;
    }
    set value(newValue) {
        this._value = newValue === null || newValue === undefined ? '' : String(newValue);
    }

    get selectedLabel() {
        const selected = this._options.find((option) => String(option.value) === String(this._value));
        return selected ? selected.label : '';
    }

    get hasValue() {
        return this._value !== '' && this._value !== null && this._value !== undefined;
    }

    get triggerText() {
        return this.selectedLabel || this.placeholder;
    }

    get triggerTextClass() {
        return this.selectedLabel ? 'sp-trigger-text' : 'sp-trigger-text sp-placeholder';
    }

    get controlClass() {
        return this.spError ? 'sp-control sp-control-error' : 'sp-control';
    }

    /**
     * lightning-input-compatible validity API so parent screens (e.g. the
     * register page) can drive inline errors via setCustomValidity/reportValidity
     * exactly like they do for lightning-input.
     */
    @api
    setCustomValidity(message) {
        this._customValidity = message || '';
    }

    @api
    reportValidity() {
        this.spError = this._customValidity || '';
        return !this._customValidity;
    }

    @api
    checkValidity() {
        return !this._customValidity;
    }

    get filteredOptions() {
        const term = (this.searchText || '').trim().toLowerCase();
        let list = this._options;
        if (term) {
            list = this._options.filter((option) => (option.label || '').toLowerCase().includes(term));
        }
        return list.map((option, index) => ({
            label: option.label,
            value: option.value,
            key: option.value,
            itemClass:
                index === this.activeIndex
                    ? 'sp-option is-active'
                    : String(option.value) === String(this._value)
                      ? 'sp-option is-selected'
                      : 'sp-option'
        }));
    }

    get hasFilteredOptions() {
        return this.filteredOptions.length > 0;
    }

    get wrapperClass() {
        let classes = 'sp-wrapper';
        if (this.isOpen) classes += ' is-open';
        if (this.disabled) classes += ' is-disabled';
        return classes;
    }

    connectedCallback() {
        this._boundReposition = () => {
            if (this.isOpen) this.positionDropdown();
        };
        window.addEventListener('resize', this._boundReposition);
        // Capture phase so scrolls inside any ancestor reposition the dropdown.
        window.addEventListener('scroll', this._boundReposition, true);
    }

    disconnectedCallback() {
        if (this._boundReposition) {
            window.removeEventListener('resize', this._boundReposition);
            window.removeEventListener('scroll', this._boundReposition, true);
        }
        document.removeEventListener('click', this.handleDocumentClick);
    }

    renderedCallback() {
        if (this.isOpen) {
            this.positionDropdown();
            if (this._scrollActiveIntoView) {
                this._scrollActiveIntoView = false;
                const active = this.template.querySelector('.sp-option.is-active');
                if (active && typeof active.scrollIntoView === 'function') {
                    active.scrollIntoView({ block: 'nearest' });
                }
            }
        }
    }

    // Keep clicks inside the component from reaching the document-level close handler.
    handleContainerClick(event) {
        event.stopPropagation();
    }

    handleTriggerClick(event) {
        event.stopPropagation();
        if (this.disabled) return;
        this.toggle();
    }

    handleTriggerKeydown(event) {
        if (this.disabled) return;
        if (!this.isOpen && (event.key === 'Enter' || event.key === ' ' || event.key === 'ArrowDown')) {
            event.preventDefault();
            this.open();
        }
    }

    handleSearchInput(event) {
        this.searchText = event.target.value || '';
        this.activeIndex = -1;
    }

    handleSearchKeydown(event) {
        if (!this.isOpen) return;
        const options = this.filteredOptions;
        switch (event.key) {
            case 'ArrowDown':
                event.preventDefault();
                this.activeIndex = options.length ? Math.min(this.activeIndex + 1, options.length - 1) : -1;
                this._scrollActiveIntoView = true;
                break;
            case 'ArrowUp':
                event.preventDefault();
                this.activeIndex = options.length ? Math.max(this.activeIndex - 1, 0) : -1;
                this._scrollActiveIntoView = true;
                break;
            case 'Enter':
                event.preventDefault();
                if (this.activeIndex >= 0 && this.activeIndex < options.length) {
                    this.selectValue(options[this.activeIndex].value);
                }
                break;
            case 'Escape':
                event.preventDefault();
                this.close();
                this.focusTrigger();
                break;
            default:
                break;
        }
    }

    handleOptionMouseDown(event) {
        // mousedown + preventDefault keeps the search input from blurring before the pick registers.
        event.preventDefault();
        event.stopPropagation();
        this.selectValue(event.currentTarget.dataset.value || '');
    }

    handleClearClick(event) {
        event.stopPropagation();
        if (this.disabled) return;
        this.selectValue('');
    }

    handleDocumentClick = () => {
        if (this.isOpen) this.close();
    };

    toggle() {
        if (this.isOpen) {
            this.close();
        } else {
            this.open();
        }
    }

    open() {
        this.isOpen = true;
        this.searchText = '';
        this.activeIndex = -1;
        document.addEventListener('click', this.handleDocumentClick);
        this.positionDropdown();
        // Focus the search box once the dropdown has rendered.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            const input = this.template.querySelector('.sp-search');
            if (input) input.focus();
        });
    }

    close() {
        if (!this.isOpen) return;
        this.isOpen = false;
        this.searchText = '';
        this.activeIndex = -1;
        document.removeEventListener('click', this.handleDocumentClick);
    }

    selectValue(selectedValue) {
        this._value = selectedValue;
        // Clear any inline validation error once the user picks a value.
        this._customValidity = '';
        this.spError = '';
        this.close();
        this.dispatchEvent(new CustomEvent('change', { detail: { value: this._value } }));
    }

    focusTrigger() {
        const trigger = this.template.querySelector('.sp-control');
        if (trigger) trigger.focus();
    }

    positionDropdown() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const trigger = this.template.querySelector('.sp-control');
            const dropdown = this.template.querySelector('.sp-dropdown');
            if (trigger && dropdown) {
                const rect = trigger.getBoundingClientRect();
                dropdown.style.left = `${rect.left}px`;
                dropdown.style.width = `${rect.width}px`;
                const dropdownHeight = dropdown.offsetHeight || 300;
                const spaceBelow = window.innerHeight - rect.bottom;
                const spaceAbove = rect.top;
                // Decide direction against a consistent reference height (not the
                // actual option count) so fields on the SAME row — e.g. Select
                // Programme + Year of Graduation — always open the same way.
                const openUp = spaceBelow < 300 && spaceAbove > spaceBelow;
                if (openUp) {
                    dropdown.style.top = `${Math.max(8, rect.top - dropdownHeight - 4)}px`;
                } else {
                    dropdown.style.top = `${rect.bottom + 4}px`;
                }
            }
        });
    }
}