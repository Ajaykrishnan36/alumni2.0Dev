/**
 * Horizontal role selector (Students, Alumni, Parents, etc.)
 * Emits `rolechange` with detail.value on selection.
 */
import { LightningElement, api } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenRolePills extends LightningElement {
    @api value = 'STUDENTS';

    /**
     * Array<{ label, value, count?: number }>
     */
    @api roles = [];

    get rolesWithState() {
        return (this.roles || []).map((r) => {
            const isActive = r.value === this.value;
            return {
                ...r,
                className: isActive ? 'pill pillActive' : 'pill',
                count: r.count || 0
            };
        });
    }

    handleRoleClick(event) {
        const next = event.currentTarget.dataset.value;
        if (!next || next === this.value) {
            return;
        }
        this.dispatchEvent(new CustomEvent('rolechange', { detail: { value: next } }));
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