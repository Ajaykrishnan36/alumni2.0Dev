import { LightningElement, api } from 'lwc';

const VARIANT_DEFAULTS = {
    page:  { rows: 3, withTitle: true,  withBreadcrumb: true  },
    list:  { rows: 4, withTitle: false, withBreadcrumb: false },
    grid:  { rows: 6, withTitle: false, withBreadcrumb: false },
    table: { rows: 5, withTitle: false, withBreadcrumb: false },
    card:  { rows: 1, withTitle: false, withBreadcrumb: false }
};

/**
 * Reusable shimmer skeleton.
 *
 * Usage:
 *   <c-ken-skeleton-loader variant="page"  rows="4"></c-ken-skeleton-loader>
 *   <c-ken-skeleton-loader variant="grid"  rows="6"></c-ken-skeleton-loader>
 *   <c-ken-skeleton-loader variant="list"  rows="5"></c-ken-skeleton-loader>
 *   <c-ken-skeleton-loader variant="table" rows="6"></c-ken-skeleton-loader>
 *   <c-ken-skeleton-loader variant="card"></c-ken-skeleton-loader>
 *
 * Render conditionally:
 *   <template lwc:if={loading}>
 *     <c-ken-skeleton-loader variant="page" rows="3"></c-ken-skeleton-loader>
 *   </template>
 *   <template lwc:else>
 *     ...real content...
 *   </template>
 */
export default class KenSkeletonLoader extends LightningElement {
    @api variant = 'page';
    @api rows;
    @api withTitle;
    @api withBreadcrumb;

    get _config() {
        const defaults = VARIANT_DEFAULTS[this.variant] || VARIANT_DEFAULTS.page;
        return {
            rows: this.rows != null ? Number(this.rows) : defaults.rows,
            withTitle: this.withTitle != null ? this._asBool(this.withTitle) : defaults.withTitle,
            withBreadcrumb: this.withBreadcrumb != null ? this._asBool(this.withBreadcrumb) : defaults.withBreadcrumb
        };
    }

    _asBool(v) {
        if (typeof v === 'boolean') return v;
        return String(v).toLowerCase() !== 'false';
    }

    get rowKeys() {
        const count = Math.max(1, this._config.rows || 1);
        return Array.from({ length: count }, (_, i) => `sk-${i}`);
    }

    get showTitle() { return this._config.withTitle; }
    get showBreadcrumb() { return this._config.withBreadcrumb; }

    get isPage()  { return this.variant === 'page'; }
    get isList()  { return this.variant === 'list'; }
    get isGrid()  { return this.variant === 'grid'; }
    get isTable() { return this.variant === 'table'; }
    get isCard()  { return this.variant === 'card'; }
}