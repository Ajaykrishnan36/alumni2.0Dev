import { LightningElement, api, track } from 'lwc';

// Matches kenNetworkPage's breakpoint rather than the 768px used on the event
// page, so the back button appears exactly when the network page itself switches
// to its mobile layout. A one-pixel disagreement would leave a width where the
// list is hidden but the way back is not shown.
const MOBILE_QUERY = '(max-width: 767px)';

export default class KenProfilePage extends LightningElement {
    @api profileId;
    // Supplied by kenNetworkPage when the visitor tapped a card. Blank after a
    // page refresh, where only profileId survives in the URL, so the header
    // falls back to a generic title rather than showing an empty bar.
    @api profileName;

    @track isMobile = false;

    _mediaQuery;
    _boundSync;

    connectedCallback() {
        this._boundSync = this.syncIsMobile.bind(this);
        if (typeof window !== 'undefined' && window.matchMedia) {
            this._mediaQuery = window.matchMedia(MOBILE_QUERY);
            this.isMobile = this._mediaQuery.matches;
            // addEventListener is not available on MediaQueryList in older
            // WebKit, which is exactly where this runs - mobile Safari.
            if (this._mediaQuery.addEventListener) {
                this._mediaQuery.addEventListener('change', this._boundSync);
            } else if (this._mediaQuery.addListener) {
                this._mediaQuery.addListener(this._boundSync);
            }
        }
        if (typeof window !== 'undefined') {
            window.addEventListener('resize', this._boundSync);
        }
    }

    disconnectedCallback() {
        if (this._mediaQuery) {
            if (this._mediaQuery.removeEventListener) {
                this._mediaQuery.removeEventListener('change', this._boundSync);
            } else if (this._mediaQuery.removeListener) {
                this._mediaQuery.removeListener(this._boundSync);
            }
        }
        if (typeof window !== 'undefined') {
            window.removeEventListener('resize', this._boundSync);
        }
    }

    syncIsMobile() {
        this.isMobile = this._mediaQuery
            ? this._mediaQuery.matches
            : typeof window !== 'undefined' && window.innerWidth <= 767;
    }

    get headerTitle() {
        const name = (this.profileName || '').trim();
        return name || 'Profile';
    }

    /**
     * kenNetworkPage already listens for this and navigates back to the network
     * list, clearing profileId from the URL - it just had nothing dispatching it
     * until now, so its onback handler was dead.
     */
    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }
}