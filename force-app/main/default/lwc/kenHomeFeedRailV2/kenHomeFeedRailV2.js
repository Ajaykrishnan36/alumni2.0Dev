import { LightningElement, api } from 'lwc';

export default class KenHomeFeedRailV2 extends LightningElement {
    static renderMode = 'light';
    @api items = [];
    @api showVerify = false;
    @api showConnect = false;

    get hasItems() { return Array.isArray(this.items) && this.items.length > 0; }

    handleAll() {
        this.dispatchEvent(new CustomEvent('viewall', { bubbles: true, composed: true }));
    }
    handleItem(event) {
        const key = event.currentTarget.dataset.key;
        this.dispatchEvent(new CustomEvent('itemclick', {
            detail: { key },
            bubbles: true,
            composed: true
        }));
    }
    // If a real feed image 404s, hide the <img> so the coloured category icon
    // underneath shows through — the user never sees a broken-image glyph.
    handleImgError(event) {
        if (event && event.target) event.target.style.display = 'none';
    }
}