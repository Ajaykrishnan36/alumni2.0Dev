/**
 * Left navigation used in Target Audience Selection.
 * Emits `navchange` with detail.value when user selects a new section.
 */
import { LightningElement, api } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenAudienceLeftNav extends LightningElement {
    @api value = 'ROLE_DETAILS';

    _baseItems = [
        { label: 'Role & Details', value: 'ROLE_DETAILS' },
        { label: 'Groups', value: 'GROUPS' },
        { label: 'Specific Individuals', value: 'INDIVIDUALS' },
        { label: 'Saved Audience', value: 'SAVED' }
    ];

    get items() {
        return this._baseItems.map((i) => {
            const isActive = i.value === this.value;
            return {
                ...i,
                isActive,
                className: isActive ? 'navButton navButtonActive' : 'navButton'
            };
        });
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

    handleClick(event) {
        const next = event.currentTarget.dataset.value;
        if (!next || next === this.value) {
            return;
        }
        this.dispatchEvent(new CustomEvent('navchange', { detail: { value: next } }));
    }
}