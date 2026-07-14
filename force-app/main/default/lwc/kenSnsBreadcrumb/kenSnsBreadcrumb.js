import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

/**
 * Reusable Service & Support breadcrumb — matches the SnS portal's
 * "Home > Page" muted-text pattern.
 *
 * Usage:
 *   <c-ken-sns-breadcrumb items={crumbs} onnavigate={handleCrumbClick}></c-ken-sns-breadcrumb>
 *
 *   crumbs = [
 *     { label: 'Home',             pageName: 'Home' },
 *     { label: 'Service & Support', url: '/service-support' },
 *     { label: 'Request for a Service' }                  // last item — current page, not clickable
 *   ];
 *
 * Each clickable crumb auto-navigates via comm__namedPage when `pageName` is set,
 * or via a relative URL when `url` is set. Parents can also listen to the
 * `navigate` event to override or do SPA routing.
 */
export default class KenSnsBreadcrumb extends NavigationMixin(LightningElement) {
    @api items = [];

    get computedItems() {
        const list = Array.isArray(this.items) ? this.items : [];
        return list.map((item, index) => {
            const isLast = index === list.length - 1;
            return {
                ...item,
                index,
                key: `bc-${index}-${(item && item.label) || ''}`,
                isClickable: !isLast,
                showSeparator: !isLast
            };
        });
    }

    handleClick(event) {
        event.preventDefault();
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const item = (this.items || [])[index];
        if (!item) return;

        this.dispatchEvent(new CustomEvent('navigate', {
            detail: { ...item, index }
        }));

        // Prefer URL-based navigation when provided — bulletproof, doesn't depend on
        // page API names being exactly right in Experience Builder.
        if (item.url) {
            const targetUrl = this._buildUrl(item.url);
            try {
                this[NavigationMixin.Navigate]({
                    type: 'standard__webPage',
                    attributes: { url: targetUrl }
                });
                return;
            } catch (e) {
                try {
                    window.location.assign(targetUrl);
                    return;
                } catch (e2) {
                    // Fall through to pageName below
                }
            }
        }

        if (item.pageName) {
            try {
                this[NavigationMixin.Navigate]({
                    type: 'comm__namedPage',
                    attributes: { name: item.pageName },
                    state: item.state || {}
                });
            } catch (e) {
                // Parent's onnavigate handler can take over
            }
        }
    }

    _buildUrl(path) {
        if (!path) return '/';
        if (/^https?:\/\//i.test(path)) return path;
        const cleanPath = String(path).replace(/^\/+/, '');
        try {
            const parts = window.location.pathname.split('/').filter(Boolean);
            const sitePrefix = parts.length ? `/${parts[0]}` : '';
            return `${sitePrefix}/${cleanPath}`;
        } catch (e) {
            return `/${cleanPath}`;
        }
    }
}