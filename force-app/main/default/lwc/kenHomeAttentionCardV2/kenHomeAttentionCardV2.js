import { LightningElement, api } from 'lwc';

const SEVERITY_TO_TONE = {
    high:   { dot: 'rose',    badge: 'rose',    icon: '⚠' },
    medium: { dot: 'amber',   badge: 'amber',   icon: '!'  },
    low:    { dot: 'sky',     badge: 'sky',     icon: '·'  }
};

export default class KenHomeAttentionCardV2 extends LightningElement {
    static renderMode = 'light';
    @api items = [];

    get hasItems() {
        return Array.isArray(this.items) && this.items.length > 0;
    }
    get headerCount() {
        const n = this.hasItems ? this.items.length : 0;
        return `${n} need${n === 1 ? 's' : ''} action`;
    }
    get headerTitle() { return 'Needs attention'; }
    get decoratedItems() {
        if (!this.hasItems) return [];
        return this.items.map((i) => {
            const sev = (i.severity || 'low').toLowerCase();
            const tone = SEVERITY_TO_TONE[sev] || SEVERITY_TO_TONE.low;
            return {
                ...i,
                key: i.id,
                dotClass:    `att-dot att-dot--${tone.dot}`,
                badgeClass:  `att-badge att-badge--${tone.badge}`,
                badgeLabel:  sev.toUpperCase(),
                iconText:    tone.icon,
                btnClass:    sev === 'high' ? 'att-btn att-btn--primary' : 'att-btn',
                cta:         i.ctaLabel || 'View'
            };
        });
    }

    handleAll() {
        this.dispatchEvent(new CustomEvent('viewall', { bubbles: true, composed: true }));
    }
    handleRow(event) {
        const id  = event.currentTarget.dataset.id;
        const url = event.currentTarget.dataset.url;
        this.dispatchEvent(new CustomEvent('rowaction', {
            detail: { id, url },
            bubbles: true,
            composed: true
        }));
    }
}