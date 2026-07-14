/**
 * Renders the "Create Custom {Role} Group" UI.
 * Parent owns the state; this component is a purely presentational + event emitter.
 */
import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenCustomGroupBuilder extends LightningElement {
    connectedCallback() {
        this._boundKeydown = this._handleKeydown.bind(this);
        document.addEventListener('keydown', this._boundKeydown);
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            // eslint-disable-next-line no-console
            console.log('Error getting primary color');
        });
    }
    disconnectedCallback() {
        document.removeEventListener('keydown', this._boundKeydown);
    }
    _handleKeydown(event) {
        if (this.openMenuId && event.key === 'Escape') {
            this.openMenuId = null;
        }
    }
    /** Display label for the role (e.g., "Students"). */
    @api roleLabel;

    /**
     * Draft group being edited:
     * { id, displayName, selections: { [fieldKey]: string[] | string } }
     */
    @api draftGroup;

    /**
     * Field config array:
     * [{ key, label, placeholder, type: 'multiselect'|'search', options?: [] }]
     */
    @api fieldConfig = [];

    /** Saved groups list for this role. */
    _savedGroups = [];
    expandedMap = {};
    @track openMenuId = null;

    @api
    get savedGroups() {
        return this._savedGroups;
    }
    set savedGroups(value) {
        this._savedGroups = Array.isArray(value) ? value : [];
        const next = { ...this.expandedMap };
        this._savedGroups.forEach((g) => {
            if (next[g.id] === undefined) {
                next[g.id] = true;
            }
        });
        this.expandedMap = next;
    }

    /** Show the "Add Another Group" button after Group 1 is saved. */
    @api showAddAnother = false;
    /** Tracks whether any group has been created for label purposes. */
    @api hasAnyGroup = false;

    get hasSavedGroups() {
        return Array.isArray(this._savedGroups) && this._savedGroups.length > 0;
    }

    get groupTitle() {
        if (this.draftGroup && this.draftGroup.displayName) {
            return this.draftGroup.displayName;
        }
        const role = this.roleLabel || 'Audience';
        return `${role} Audience`;
    }

    get addAnotherLabel() {
        const role = this.roleLabel || 'Audience';
        return this.hasAnyGroup ? `Add Another ${role} Audience` : `Add ${role} Audience`;
    }

    get saveGroupLabel() {
        return 'Add to Audience';
    }

    get savedGroupsWithState() {
        return (this._savedGroups || []).map((g) => {
            const expanded = !!this.expandedMap[g.id];
            return {
                ...g,
                displayName: g.title || g.name,
                expanded,
                menuOpen: this.openMenuId === g.id,
                chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
                hasCriteria: Array.isArray(g.criteria) && g.criteria.length > 0
            };
        });
    }

    /**
     * Merge field config with draft selections + options, in a format convenient for the template.
     */
    get fields() {
        const selections = (this.draftGroup && this.draftGroup.selections) || {};
        return (this.fieldConfig || []).map((f) => {
            const value = selections[f.key];
            const isSearch = f.type === 'search';
            const isMulti = f.type === 'multiselect';
            const expectsArray = isMulti || isSearch;
            const normalizedValue = expectsArray
                ? (Array.isArray(value) ? value : (value ? [value] : []))
                : (value || '');
            return {
                ...f,
                isMulti,
                isSearch,
                options: f.options || [],
                value: normalizedValue
            };
        });
    }

    handleMultiChange(event) {
        const key = event.currentTarget.dataset.key;
        const value = event.detail && event.detail.value ? event.detail.value : [];
        this.dispatchEvent(new CustomEvent('draftchange', { detail: { key, value } }));
    }

    handleFieldSearch(event) {
        const key = event.currentTarget.dataset.key;
        const value = event.detail && typeof event.detail.value === 'string' ? event.detail.value : '';
        this.dispatchEvent(
            new CustomEvent('fieldsearch', {
                detail: { key, value },
                bubbles: true,
                composed: true
            })
        );
    }

    handleSaveGroup(event) {
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }
        this.dispatchEvent(new CustomEvent('savegroup'));
    }

    handleAddAnother(event) {
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }
        this.dispatchEvent(new CustomEvent('addanother'));
    }

    handleEditGroup(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('editgroup', { detail: { id } }));
    }

    handleSavedAction(event) {
        const id = event.currentTarget.dataset.id;
        const action = event.detail && event.detail.value;
        if (!id || !action) {
            return;
        }
        if (action === 'edit') {
            this.dispatchEvent(new CustomEvent('editgroup', { detail: { id } }));
            return;
        }
        if (action === 'delete') {
            this.dispatchEvent(new CustomEvent('deletegroup', { detail: { id } }));
        }
    }

    toggleSavedMenu(event) {
        const id = event.currentTarget.dataset.id;
        this.openMenuId = this.openMenuId === id ? null : id;
    }

    handleSavedActionClick(event) {
        const id = event.currentTarget.dataset.id;
        const action = event.currentTarget.dataset.action;
        this.openMenuId = null;
        if (!id || !action) {
            return;
        }
        if (action === 'edit') {
            this.dispatchEvent(new CustomEvent('editgroup', { detail: { id } }));
        } else if (action === 'delete') {
            this.dispatchEvent(new CustomEvent('deletegroup', { detail: { id } }));
        }
    }

    handleCloseSavedMenu(event) {
        if (event.type === 'keydown' && event.key !== 'Escape') {
            return;
        }
        this.openMenuId = null;
    }

    handleToggleSaved(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) {
            return;
        }
        const next = { ...this.expandedMap };
        next[id] = !next[id];
        this.expandedMap = next;
    }
}