/**
 * Generic multi-select picklist combobox.
 * - Displays selected values as pills.
 * - Allows searching and selecting multiple options.
 * - Emits `change` event with `detail.value` (string[]).
 */
import { LightningElement, api } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenMultiSelectPicklist extends LightningElement {
    /** Label shown above the control. */
    @api label;

    /** Placeholder text shown when no selection exists. */
    @api placeholder = 'Choose';

    /** Available options: Array<{ label: string, value: string }>. */
    @api options = [];

    /** Selected values (string[]). */
    @api value = [];

    /** Disable user interaction. */
    @api disabled = false;

    /** Search mode: 'local' (default) or 'server'. */
    @api searchMode = 'local';

    isOpen = false;
    searchText = '';
    _boundDocClick;
    _boundGlobalOpen;
    _instanceId = `${Date.now()}_${Math.floor(Math.random() * 100000)}`;

    connectedCallback() {
        // Close dropdown on outside click. Registered on the CAPTURE phase
        // (the `true` 3rd arg) rather than bubble — this component is used
        // inside popups/modals that call e.stopPropagation() on their own
        // container click handler (so an inner click doesn't also close the
        // whole popup via its backdrop). stopPropagation() during bubble
        // only blocks listeners later in the bubble chain; it can't stop a
        // capture-phase listener on document, which always runs first,
        // before the event even reaches the click target. Without capture,
        // clicking anywhere inside such a popup other than this dropdown
        // would never reach this listener, so it'd never close.
        this._boundDocClick = this.handleDocumentClick.bind(this);
        document.addEventListener('click', this._boundDocClick, true);
        this._boundGlobalOpen = this.handleGlobalOpen.bind(this);
        window.addEventListener('ms-open', this._boundGlobalOpen);
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._boundDocClick, true);
        window.removeEventListener('ms-open', this._boundGlobalOpen);
    }

    get comboboxClass() {
        const base = 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click';
        return this.isOpen ? `${base} slds-is-open` : base;
    }

    get hasSelection() {
        return Array.isArray(this.value) && this.value.length > 0;
    }

    get displayValue() {
        if (!this.hasSelection) {
            return '';
        }
        const byValue = new Map((this.options || []).map((o) => [o.value, o.label]));
        return (this.value || []).map((v) => byValue.get(v) || v).join(', ');
    }

    get pillItems() {
        const byValue = new Map((this.options || []).map((o) => [o.value, o.label]));
        return (this.value || []).map((v) => ({ label: byValue.get(v) || v, name: v }));
    }

    get filteredOptions() {
        const q = (this.searchText || '').trim().toLowerCase();
        const selectedSet = new Set(this.value || []);
        return (this.options || [])
            .filter((o) => !q || (o.label || '').toLowerCase().includes(q))
            .map((o) => ({
                label: o.label,
                value: o.value,
                selected: selectedSet.has(o.value),
                id: `${this._instanceId}_${o.value}`
            }));
    }

    get isEmpty() {
        return this.filteredOptions.length === 0;
    }

    get isServerSearch() {
        return String(this.searchMode || '').toLowerCase() === 'server';
    }

    get showSelectAll() {
        return Array.isArray(this.options) && this.options.length > 0;
    }

    /**
     * "All" always operates on whatever is currently visible (filteredOptions),
     * not the full options set — for a picklist with an active local text
     * filter, or a server-search field where options are only ever the
     * current search results, "All" should mean "everything shown right now."
     */
    get isAllSelected() {
        const visible = this.filteredOptions;
        if (!visible.length) {
            return false;
        }
        const selectedSet = new Set(this.value || []);
        return visible.every((o) => selectedSet.has(o.value));
    }

    handleSelectAllClick(event) {
        event.stopPropagation();
        if (this.disabled) {
            return;
        }
        const visibleValues = this.filteredOptions.map((o) => o.value);
        if (this.isAllSelected) {
            // Only deselect what's currently visible — selections made during
            // an earlier/different search stay untouched, same as manual picks.
            const visibleSet = new Set(visibleValues);
            this.dispatchChange((this.value || []).filter((v) => !visibleSet.has(v)));
        } else {
            const next = new Set(this.value || []);
            visibleValues.forEach((v) => next.add(v));
            this.dispatchChange(Array.from(next));
        }
    }

    toggleOpen(event) {
        event.stopPropagation();
        if (this.disabled) {
            return;
        }
        this.isOpen = !this.isOpen;
        if (this.isOpen) {
            // Reset search each time it opens.
            this.searchText = '';
            window.dispatchEvent(new CustomEvent('ms-open', { detail: { id: this._instanceId } }));
            if (this.isServerSearch) {
                this.emitSearch('');
            }
        }
    }

    handleSearchInput(event) {
        event.stopPropagation();
        const nextValue = event.detail && typeof event.detail.value === 'string'
            ? event.detail.value
            : event.target.value;
        this.searchText = nextValue;
        if (this.isServerSearch) {
            this.emitSearch(this.searchText);
        }
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    handleOptionRowClick(event) {
        event.stopPropagation();
        if (this.disabled) {
            return;
        }
        const selectedValue = event.currentTarget && event.currentTarget.dataset
            ? event.currentTarget.dataset.value
            : null;
        if (!selectedValue) {
            return;
        }
        const next = new Set(this.value || []);
        if (next.has(selectedValue)) {
            next.delete(selectedValue);
        } else {
            next.add(selectedValue);
        }
        this.dispatchChange(Array.from(next));
    }

    handlePillRemove(event) {
        const name = event.detail && event.detail.item && event.detail.item.name;
        if (!name) {
            return;
        }
        const next = (this.value || []).filter((v) => v !== name);
        this.dispatchChange(next);
    }

    handlePillRemoveClick(event) {
        event.stopPropagation();
        const name = event.currentTarget && event.currentTarget.dataset
            ? event.currentTarget.dataset.name
            : null;
        if (!name) {
            return;
        }
        const next = (this.value || []).filter((v) => v !== name);
        this.dispatchChange(next);
    }

    dispatchChange(nextValues) {
        this.value = Array.isArray(nextValues) ? nextValues : [];
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: this.value }
            })
        );
    }

    emitSearch(value) {
        this.dispatchEvent(
            new CustomEvent('search', {
                detail: { value },
                bubbles: true,
                composed: true
            })
        );
    }

    handleDocumentClick(event) {
        // Close if click happens outside this component.
        if (!this.isOpen) {
            return;
        }
        const root = this.template && this.template.host;
        const path = event.composedPath ? event.composedPath() : [];
        if (root && !root.contains(event.target) && !path.includes(root)) {
            this.isOpen = false;
        }
    }

    handleGlobalOpen(event) {
        const id = event.detail && event.detail.id;
        if (!id || id === this._instanceId) {
            return;
        }
        if (this.isOpen) {
            this.isOpen = false;
        }
    }
}