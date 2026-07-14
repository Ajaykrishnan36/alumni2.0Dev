import { LightningElement, api } from 'lwc';

const DEFAULT_PHOTO = 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=600&q=80';

export default class KenHomeMatchHeroV2 extends LightningElement {
    static renderMode = 'light';

    @api eyebrow = '';
    @api title = '';
    @api meta = '';
    @api quote = '';
    @api ctaLabel = 'Read full story';
    @api secondaryCtaLabel = 'Nominate next month';

    // Pass a CSP-safe URL (Salesforce Content Asset, Static Resource, or Unsplash).
    // Falls back to a verified working portrait so the picture is never blank.
    _imageSrc = DEFAULT_PHOTO;
    @api
    get imageSrc() { return this._imageSrc; }
    set imageSrc(v) { this._imageSrc = v && String(v).trim() ? v : DEFAULT_PHOTO; }

    get imgStyle() {
        return `background-image: url('${this._imageSrc}');`;
    }

    handleContinue() {
        this.dispatchEvent(new CustomEvent('continuesetup', { bubbles: true, composed: true }));
    }
    handleNominate() {
        this.dispatchEvent(new CustomEvent('nominate', { bubbles: true, composed: true }));
    }
}