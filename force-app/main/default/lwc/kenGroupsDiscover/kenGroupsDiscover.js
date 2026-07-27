import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenGroupsDiscover extends LightningElement {
    @api suggestedGroups = [];
    @api isMobileView = false;
    @track currentSuggestedIndex = 0;

    get currentSuggestedGroup() {
        const list = this.suggestedGroups || [];
        if (!list.length) return null;
        const idx = ((this.currentSuggestedIndex % list.length) + list.length) % list.length;
        return list[idx];
    }

    get suggestedCount() {
        return (this.suggestedGroups || []).length;
    }

    get suggestedCountFormatted() {
        const n = this.suggestedCount;
        return n < 10 ? '0' + n : String(n);
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {});
    }

    // Card width (300px) + gap (24px) = one page scroll unit
    _cardScrollUnit = 324;

    handlePrev() {
        if (this.isMobileView) {
            const len = (this.suggestedGroups || []).length;
            if (len === 0) return;
            this.currentSuggestedIndex = (this.currentSuggestedIndex - 1 + len) % len;
        } else {
            const container = this.template.querySelector('.cards-scroll-container');
            if (container) container.scrollBy({ left: -this._cardScrollUnit, behavior: 'smooth' });
        }
    }

    handleGroupClick(event) {
        const groupId = event.currentTarget.dataset.groupId;
        if (!groupId) return;
        this.dispatchEvent(new CustomEvent('groupclick', {
            detail: { groupId },
            bubbles: true,
            composed: true
        }));
    }

    handleNext() {
        if (this.isMobileView) {
            const len = (this.suggestedGroups || []).length;
            if (len === 0) return;
            this.currentSuggestedIndex = (this.currentSuggestedIndex + 1) % len;
        } else {
            const container = this.template.querySelector('.cards-scroll-container');
            if (container) container.scrollBy({ left: this._cardScrollUnit, behavior: 'smooth' });
        }
    }
}