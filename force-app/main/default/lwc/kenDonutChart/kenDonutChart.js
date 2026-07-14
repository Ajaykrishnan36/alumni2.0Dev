import { LightningElement, api, track } from 'lwc';

const COLORS = [
    '#5B9BD5', '#52B788', '#E07878', '#E89C50', '#9D7FCC',
    '#3ABAC4', '#E07AAA', '#7CBD52', '#E5B840', '#52A8E0',
    '#B07FCC', '#E06060', '#40BDA0', '#CC8A52'
];

const CX = 60, CY = 60, R_OUTER = 46, R_INNER = 28;
const FUNNEL_CX = 60, FUNNEL_MAX_W = 110, FUNNEL_H = 160;

function toRad(deg) { return (deg - 90) * Math.PI / 180; }
function pt(r, angle) {
    return { x: CX + r * Math.cos(toRad(angle)), y: CY + r * Math.sin(toRad(angle)) };
}

function slicePath(startAngle, endAngle) {
    const full = Math.abs(endAngle - startAngle) >= 359.9;
    if (full) {
        const o1 = pt(R_OUTER, 0), o2 = pt(R_OUTER, 180);
        const i1 = pt(R_INNER, 180), i2 = pt(R_INNER, 0);
        return `M ${o1.x} ${o1.y} A ${R_OUTER} ${R_OUTER} 0 1 1 ${o2.x} ${o2.y} A ${R_OUTER} ${R_OUTER} 0 1 1 ${o1.x} ${o1.y} Z`
             + ` M ${i1.x} ${i1.y} A ${R_INNER} ${R_INNER} 0 1 0 ${i2.x} ${i2.y} A ${R_INNER} ${R_INNER} 0 1 0 ${i1.x} ${i1.y} Z`;
    }
    const large = (endAngle - startAngle) > 180 ? 1 : 0;
    const os = pt(R_OUTER, startAngle), oe = pt(R_OUTER, endAngle);
    const is_ = pt(R_INNER, endAngle), ie = pt(R_INNER, startAngle);
    return [
        `M ${os.x} ${os.y}`,
        `A ${R_OUTER} ${R_OUTER} 0 ${large} 1 ${oe.x} ${oe.y}`,
        `L ${is_.x} ${is_.y}`,
        `A ${R_INNER} ${R_INNER} 0 ${large} 0 ${ie.x} ${ie.y}`,
        'Z'
    ].join(' ');
}

export default class KenDonutChart extends LightningElement {
    @api title       = '';
    @api description = '';
    @api isLoading   = false;
    @api dimension   = '';
    @api chartType   = 'donut'; // 'donut' | 'funnel'
    @api showExport  = false;

    @track _tooltip = null;

    _data = [];
    @api
    get data() { return this._data; }
    set data(val) { this._data = val || []; }

    get hasData() { return this._data && this._data.length > 0 && this.total > 0; }
    get isDonut()  { return this.chartType !== 'funnel'; }
    get isFunnel() { return this.chartType === 'funnel'; }

    get total() {
        return (this._data || []).reduce((s, d) => s + (d.value || 0), 0);
    }

    // ── Tooltip ────────────────────────────────────────────────────────────────
    get tooltipVisible() { return this._tooltip !== null; }
    get tooltipStyle() {
        if (!this._tooltip) return '';
        return `left:${this._tooltip.x}px;top:${this._tooltip.y}px`;
    }
    get tipLabel() { return this._tooltip ? this._tooltip.label : ''; }
    get tipValue() { return this._tooltip ? this._tooltip.value : 0; }
    get tipPct()   { return this._tooltip ? this._tooltip.pct   : 0; }

    handleMouseEnter(event) {
        const idx   = parseInt(event.currentTarget.dataset.idx, 10);
        const items = this.isFunnel ? this.funnelItems : this.slices;
        const item  = items[idx];
        if (!item) return;
        const card = this.template.querySelector('.chart-card');
        if (!card) return;
        const rect = card.getBoundingClientRect();
        const x    = event.clientX - rect.left;
        const y    = event.clientY - rect.top;
        const tipY = y > 80 ? y - 64 : y + 16;
        this._tooltip = { x: x + 14, y: tipY, label: item.rawLabel || item.label, value: item.value, pct: item.pct };
    }

    handleMouseLeave() {
        this._tooltip = null;
    }

    // ── Donut slices ────────────────────────────────────────────────────────────
    get slices() {
        const tot = this.total;
        if (!tot) return [];
        let angle = 0;
        return this._data.map((d, i) => {
            const sweep = (d.value / tot) * 360;
            const path  = slicePath(angle, angle + sweep);
            const pct   = Math.round((d.value / tot) * 100);
            const color = COLORS[i % COLORS.length];
            angle += sweep;
            return {
                id: i,
                label: d.label, rawLabel: d.label,
                value: d.value, pct, color, path,
                dotStyle: `background:${color}`
            };
        });
    }

    // ── Funnel segments ─────────────────────────────────────────────────────────
    get funnelItems() {
        if (!this.hasData) return [];
        const sorted  = [...this._data].sort((a, b) => (b.value || 0) - (a.value || 0));
        const maxVal  = sorted[0].value || 1;
        const tot     = this.total;
        const count   = sorted.length;
        const itemH   = Math.min(34, Math.floor((FUNNEL_H - 4) / count) - 3);
        const gap     = 3;

        return sorted.map((d, i) => {
            const topW  = Math.max(20, (d.value / maxVal) * FUNNEL_MAX_W);
            const nextV = i < sorted.length - 1 ? sorted[i + 1].value : d.value * 0.7;
            const btmW  = Math.max(14, (nextV / maxVal) * FUNNEL_MAX_W);
            const y     = 2 + i * (itemH + gap);
            const color = COLORS[i % COLORS.length];
            const topL  = FUNNEL_CX - topW / 2;
            const topR  = FUNNEL_CX + topW / 2;
            const btmL  = FUNNEL_CX - btmW / 2;
            const btmR  = FUNNEL_CX + btmW / 2;
            const path  = `M ${topL} ${y} L ${topR} ${y} L ${btmR} ${y + itemH} L ${btmL} ${y + itemH} Z`;
            const rawLabel = d.label || '';
            const label    = rawLabel.length > 14 ? rawLabel.substring(0, 14) + '…' : rawLabel;
            const pct      = Math.round((d.value / tot) * 100);
            return {
                id: i, pathId: `fp${i}`,
                path, color,
                value: d.value, pct, rawLabel, label,
                dotStyle: `background:${color}`
            };
        });
    }

    get legendItems() { return this.isFunnel ? this.funnelItems : this.slices; }

    // ── Click handlers ──────────────────────────────────────────────────────────
    handleExport() {
        this.dispatchEvent(new CustomEvent('exportcsv'));
    }

    handleSliceClick(event) {
        const idx   = parseInt(event.currentTarget.dataset.idx, 10);
        const items = this.isFunnel ? this.funnelItems : this.slices;
        const item  = items[idx];
        if (!item) return;
        this.dispatchEvent(new CustomEvent('drilldown', {
            bubbles: true,
            detail: { dimension: this.dimension, value: item.rawLabel || item.label, count: item.value }
        }));
    }

    handleLegendClick(event) {
        const idx   = parseInt(event.currentTarget.dataset.idx, 10);
        const items = this.isFunnel ? this.funnelItems : this.slices;
        const item  = items[idx];
        if (!item) return;
        this.dispatchEvent(new CustomEvent('drilldown', {
            bubbles: true,
            detail: { dimension: this.dimension, value: item.rawLabel || item.label, count: item.value }
        }));
    }
}