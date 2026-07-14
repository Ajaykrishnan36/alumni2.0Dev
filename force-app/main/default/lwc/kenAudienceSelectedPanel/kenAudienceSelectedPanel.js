/**
 * Right-side "Selected Audience" panel.
 * Groups the selection into collapsible sections (Audiences / Groups / Individuals)
 * with count badges, per-item remove menus, and a Save button pinned at the bottom.
 * Emits `remove` with detail.id and `save` when the Save button is clicked.
 */
import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

const SECTION_DEFS = [
    { key: 'AUDIENCES', label: 'Audiences Added', types: ['ALL', 'CUSTOM'] },
    { key: 'GROUPS', label: 'Groups Added', types: ['GROUP'] },
    { key: 'INDIVIDUALS', label: 'Individuals Added', types: ['INDIVIDUAL'] }
];

export default class KenAudienceSelectedPanel extends LightningElement {
    _items = [];
    expandedMap = {};
    sectionExpanded = { AUDIENCES: true, GROUPS: true, INDIVIDUALS: true };
    @track openMenuId = null;
    @api segmentationName;
    @api isDirty = false;
    @api isSaving = false;

    @api
    get items() {
        return this._items;
    }
    set items(value) {
        this._items = Array.isArray(value) ? value : [];
        const next = { ...this.expandedMap };
        this._items.forEach((item) => {
            if (next[item.id] === undefined) {
                next[item.id] = false;
            }
        });
        this.expandedMap = next;
    }

    get hasItems() {
        return Array.isArray(this._items) && this._items.length > 0;
    }

    countLabel(item) {
        if (Number.isFinite(item.memberCount)) {
            return item.memberCount === 1 ? '(1 member)' : `(${item.memberCount} members)`;
        }
        const label = item.membersLabel && String(item.membersLabel).trim();
        if (label && /\d/.test(label)) {
            return `(${label})`;
        }
        return '';
    }

    decorateItem(item) {
        const expanded = !!this.expandedMap[item.id];
        const hasCriteria = Array.isArray(item.criteria) && item.criteria.length > 0;
        return {
            ...item,
            expanded,
            hasCriteria,
            showChevron: hasCriteria,
            chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
            menuOpen: this.openMenuId === item.id,
            countLabel: this.countLabel(item),
            isIndividual: item.type === 'INDIVIDUAL'
        };
    }

    get sections() {
        const items = this._items || [];
        return SECTION_DEFS.map((def) => {
            const sectionItems = items
                .filter((item) => def.types.includes(item.type))
                .map((item) => this.decorateItem(item));
            const expanded = this.sectionExpanded[def.key] !== false;
            return {
                key: def.key,
                label: def.label,
                count: sectionItems.length,
                expanded,
                chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
                items: sectionItems
            };
        }).filter((section) => section.count > 0);
    }

    get statusLabel() {
        if (!this.hasItems) {
            return '';
        }
        return this.isDirty ? 'Unsaved changes' : (this.segmentationName ? 'Saved' : '');
    }

    get statusClass() {
        return this.isDirty ? 'statusHint statusDirty' : 'statusHint statusSaved';
    }

    get saveLabel() {
        return this.isSaving ? 'Saving...' : 'Save Audience';
    }

    get saveDisabled() {
        return !!this.isSaving;
    }

    handleToggleSection(event) {
        const key = event.currentTarget.dataset.key;
        if (!key) {
            return;
        }
        this.sectionExpanded = {
            ...this.sectionExpanded,
            [key]: this.sectionExpanded[key] === false
        };
    }

    handleToggle(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        const next = { ...this.expandedMap };
        next[id] = !next[id];
        this.expandedMap = next;
    }

    toggleMenu(event) {
        const id = event.currentTarget.dataset.id;
        this.openMenuId = this.openMenuId === id ? null : id;
    }

    handleRemoveAction(event) {
        const id = event.currentTarget.dataset.id;
        this.openMenuId = null;
        if (id) {
            this.dispatchEvent(new CustomEvent('remove', { detail: { id } }));
        }
    }

    handleCloseMenu() {
        this.openMenuId = null;
    }

    handleSaveClick() {
        this.dispatchEvent(new CustomEvent('save'));
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }
}