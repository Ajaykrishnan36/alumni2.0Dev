import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class kenNavItem extends NavigationMixin(LightningElement) {
    @api item = {};
    @api isSelected = false;

    @track href = 'javascript:void(0);';
    @track isSubMenuVisible = false;
    showTooltip = false;
    tooltipStyle = '';
    pageReference;

    connectedCallback() {
        this.isSubMenuVisible = (this.item.subMenu || []).some(sub => sub.isSelected);
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
        const { type, target } = this.item;

        if (!target) {
            // eslint-disable-next-line no-console
            console.warn(
                'Navigation menu item missing target/actionValue:',
                JSON.stringify(this.item)
            );
            return;
        }

        if (type === 'InternalLink' || type === 'ExternalLink') {
            this.pageReference = {
                type: 'standard__webPage',
                attributes: {
                    url: target
                }
            };
        }

        if (this.pageReference) {
            this[NavigationMixin.GenerateUrl](this.pageReference).then(url => {
                this.href = url;
            });
        }
    }

    get itemClass() {
        let classes = 'nav-item';

        if (this.isSelected && !this.isSubMenuVisible) {
            classes += ' selected';
        }

        if (this.isSubMenuVisible) {
            classes += ' submenu-open';
        }

        if (this.item?.isActive) {
            classes += ' active';
        }
        return classes;
    }

    get textClass() {
        return 'nav-text';
    }

    get label() {
        return this.item?.label || '';
    }

    get iconName() {
        return this.item?.iconName || '';
    }

    get hasIcon() {
        return !!this.item?.iconName;
    }

    get iconMaskStyle() {
        const url = this.item?.iconName || '';
        if (!url) return '';
        return `mask-image: url("${url}"); -webkit-mask-image: url("${url}");`;
    }

    get showDropdown() {
        return (this.item.subMenu && this.item.subMenu.length > 0);
    }

    handleClick(evt) {
        const selectEvent = new CustomEvent('itemselect', {
            detail: {
                selectedItem: this.item,
                selectedItemId: this.item.id
            },
            bubbles: true,
            composed: true
        });
        this.dispatchEvent(selectEvent);

        evt.stopPropagation();
        evt.preventDefault();

        if (this.item.label === 'Logout') {
            // sessionStorage survives a logout in the same tab (it's cleared only when the
            // tab closes), so without this the once-per-session Last_Login__c stamp in
            // kenNavBar never fires again on the next login in that tab.
            try {
                sessionStorage.removeItem('kenSessionLoginStamped');
            } catch (e) {
                // ignore storage failures
            }
            window.location.href = `${basePath}/secur/logout.jsp?retUrl/login`;
            return;
        }

        const hasSubMenu = Array.isArray(this.item.subMenu) && this.item.subMenu.length > 0;

        if (hasSubMenu) {
            this.isSubMenuVisible = !this.isSubMenuVisible;
            if (this.isSubMenuVisible) {
                this.showTooltip = false;
                this.tooltipStyle = '';
            }
            return;
        }

        if (this.pageReference) {
            this[NavigationMixin.GenerateUrl](this.pageReference).then(generatedUrl => {
                const isExternal = this.isExternalUrl(generatedUrl);
                const targetWindow = isExternal ? '_blank' : '_self';
                window.open(generatedUrl, targetWindow);
            });
        } else {
            // eslint-disable-next-line no-console
            console.error(
                `Navigation menu type "${this.item.type}" not implemented for item`,
                JSON.stringify(this.item)
            );
        }
    }

    handleMouseEnter(event) {
        if (event.relatedTarget && event.currentTarget.contains(event.relatedTarget)) {
            return;
        }

        if (this.isSubMenuVisible) {
            this.showTooltip = false;
            this.tooltipStyle = '';
            return;
        }

        this.showTooltip = true;
        const triggerEl = event.currentTarget;
        if (triggerEl) {
            const rect = triggerEl.getBoundingClientRect();
            const top = rect.top + rect.height / 2;
            const left = rect.right + 12;
            this.tooltipStyle = `top:${top}px; left:${left}px; transform: translateY(-50%);`;
        } else {
            this.tooltipStyle = '';
        }
    }

    handleMouseLeave(event) {
        if (event.relatedTarget && event.currentTarget.contains(event.relatedTarget)) {
            return;
        }

        this.showTooltip = false;
        this.tooltipStyle = '';
    }

    handleSubMenuSelect(event) {
        this.isSubMenuVisible = true;
        this.showTooltip = false;
        this.tooltipStyle = '';

        const selectedSubmenuItemId = event.detail.selectedItemId;

        const selectEvent = new CustomEvent('submenuselect', {
            detail: {
                parentItemId: this.item.id,
                selectedItem: event.detail.selectedItem,
                selectedItemId: selectedSubmenuItemId
            },
            bubbles: true,
            composed: true
        });
        this.dispatchEvent(selectEvent);
    }

    isExternalUrl(url) {
        if (!url || typeof window === 'undefined') {
            return false;
        }

        try {
            const currentOrigin = window.location?.origin || '';
            const parsedUrl = new URL(url, currentOrigin || undefined);
            return parsedUrl.origin !== currentOrigin;
        } catch (error) {
            // eslint-disable-next-line no-console
            console.warn('Failed to evaluate URL origin', error);
            return true;
        }
    }
}