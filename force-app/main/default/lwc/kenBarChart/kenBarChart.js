import { LightningElement, api, track } from 'lwc';

const COLORS = [
    '#5B9BD5', '#52B788', '#E07878', '#E89C50', '#9D7FCC',
    '#3ABAC4', '#E07AAA', '#7CBD52', '#E5B840', '#52A8E0',
    '#B07FCC', '#E06060', '#40BDA0', '#CC8A52'
];

const LABEL_W    = 100;
const RIGHT_PAD  = 50;
const TOP_PAD    = 10;
const BOTTOM_PAD = 10;
const BAR_GAP    = 4;

const V_W          = 330;
const V_H          = 215;
const V_LEFT_PAD   = 32;
const V_RIGHT_PAD  = 8;
const V_TOP_PAD    = 16;
const V_BOTTOM_PAD = 55;

export default class KenBarChart extends LightningElement {
    @api title       = '';
    @api description = '';
    @api isLoading   = false;
    @api dimension   = '';
    @api chartType   = 'horizontal'; // 'horizontal' | 'vertical' | 'line'

    @track _tooltip = null;

    _data = [];
    @api
    get data() { return this._data; }
    set data(val) { this._data = val || []; }

    get hasData()      { return this._data && this._data.length > 0; }
    get isHorizontal() { return this.chartType !== 'vertical' && this.chartType !== 'line' && this.chartType !== 'table'; }
    get isVertical()   { return this.chartType === 'vertical'; }
    get isLine()       { return this.chartType === 'line'; }
    get isTable()      { return this.chartType === 'table'; }

    get tableRows() {
        if (!this.hasData) return [];
        const maxVal = Math.max(...this._data.map(d => d.value || 0), 1);
        return this._data.map((d, i) => {
            const pct = Math.round(((d.value || 0) / maxVal) * 100);
            const color = COLORS[i % COLORS.length];
            return {
                id: i,
                rank: i + 1,
                label: d.label || '',
                value: d.value || 0,
                barStyle: `width:${pct}%;background:${color}`
            };
        });
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

    _showTooltip(event, item) {
        if (!item) return;
        const card = this.template.querySelector('.chart-card');
        if (!card) return;
        const rect  = card.getBoundingClientRect();
        const x     = event.clientX - rect.left;
        const y     = event.clientY - rect.top;
        const total = this._data.reduce((s, d) => s + (d.value || 0), 0);
        const pct   = total > 0 ? Math.round((item.value / total) * 100) : 0;
        const tipY  = y > 80 ? y - 64 : y + 16;
        this._tooltip = { x: x + 14, y: tipY, label: item.rawLabel, value: item.value, pct };
    }

    handleMouseEnter(event) {
        const idx = parseInt(event.currentTarget.dataset.idx, 10);
        let item;
        if (this.isVertical)  item = this.vBars[idx];
        else if (this.isLine) item = this.linePoints[idx];
        else                  item = this.hBars[idx];
        this._showTooltip(event, item);
    }

    handleMouseLeave() {
        this._tooltip = null;
    }

    // ── Horizontal ─────────────────────────────────────────────────────────────
    get _barH() {
        const count = Math.max(1, this._data.length);
        return Math.min(26, Math.max(14, Math.floor((280 - TOP_PAD - BOTTOM_PAD) / count) - BAR_GAP));
    }
    get hSvgHeight()   { return TOP_PAD + BOTTOM_PAD + this._data.length * (this._barH + BAR_GAP); }
    get hSvgWidth()    { return LABEL_W + RIGHT_PAD + 180; }
    get hViewBox()     { return `0 0 ${this.hSvgWidth} ${this.hSvgHeight}`; }
    get hAxisX()       { return LABEL_W; }
    get hAxisYBottom() { return this.hSvgHeight - BOTTOM_PAD; }
    get hChartRight()  { return this.hSvgWidth - RIGHT_PAD + 40; }

    get hBars() {
        if (!this.hasData) return [];
        const maxVal = Math.max(...this._data.map(d => d.value || 0), 1);
        const availW = this.hSvgWidth - LABEL_W - RIGHT_PAD;
        const bh     = this._barH;
        return this._data.map((d, i) => {
            const barW     = Math.max(2, ((d.value || 0) / maxVal) * availW);
            const y        = TOP_PAD + i * (bh + BAR_GAP);
            const rawLabel = d.label || '';
            const label    = rawLabel.length > 14 ? rawLabel.substring(0, 14) + '…' : rawLabel;
            return {
                id: i,
                x: LABEL_W, y, w: barW, h: bh,
                color: COLORS[i % COLORS.length],
                value: d.value, rawLabel, label,
                lblX: LABEL_W - 6, lblY: y + bh / 2 + 4,
                valX: LABEL_W + barW + 4, valY: y + bh / 2 + 4
            };
        });
    }

    get hGridLines() {
        const maxVal = !this.hasData ? 1 : Math.max(...this._data.map(d => d.value || 0), 1);
        const steps  = 4;
        const availW = this.hSvgWidth - LABEL_W - RIGHT_PAD;
        const yB     = this.hAxisYBottom;
        return Array.from({ length: steps + 1 }, (_, i) => {
            const frac = i / steps;
            const x    = LABEL_W + frac * availW;
            return { id: i, tid: `hgt${i}`, x1: x, y1: TOP_PAD, x2: x, y2: yB, tx: x, ty: yB + 12, label: Math.round(frac * maxVal) };
        });
    }

    // ── Vertical ───────────────────────────────────────────────────────────────
    get vViewBox() { return `0 0 ${V_W} ${V_H}`; }
    get vBaseY()   { return V_H - V_BOTTOM_PAD; }
    get vAxisX()   { return V_LEFT_PAD; }
    get vAxisX2()  { return V_W - V_RIGHT_PAD; }

    get vBars() {
        if (!this.hasData) return [];
        const count  = this._data.length;
        const availW = V_W - V_LEFT_PAD - V_RIGHT_PAD;
        const availH = V_H - V_TOP_PAD - V_BOTTOM_PAD;
        const barW   = Math.max(8, Math.floor(availW / count) - 4);
        const gap    = (availW - barW * count) / (count + 1);
        const maxVal = Math.max(...this._data.map(d => d.value || 0), 1);
        const baseY  = this.vBaseY;
        return this._data.map((d, i) => {
            const barH     = Math.max(2, ((d.value || 0) / maxVal) * availH);
            const cx       = V_LEFT_PAD + gap + i * (barW + gap) + barW / 2;
            const x        = cx - barW / 2;
            const rawLabel = d.label || '';
            const label    = rawLabel.length > 10 ? rawLabel.substring(0, 10) + '…' : rawLabel;
            return {
                id: i,
                x, y: baseY - barH, w: barW, h: barH,
                color: COLORS[i % COLORS.length],
                value: d.value, rawLabel, label,
                lblX: cx, lblY: baseY + 6,
                lblTransform: `rotate(-45, ${cx}, ${baseY + 2})`,
                valX: cx, valY: baseY - barH - 4
            };
        });
    }

    get vGridLines() {
        const maxVal = !this.hasData ? 1 : Math.max(...this._data.map(d => d.value || 0), 1);
        const steps  = 4;
        const availH = V_H - V_TOP_PAD - V_BOTTOM_PAD;
        const baseY  = this.vBaseY;
        return Array.from({ length: steps + 1 }, (_, i) => {
            const frac = i / steps;
            const y    = baseY - frac * availH;
            return { id: i, tid: `vgt${i}`, x1: V_LEFT_PAD, y1: y, x2: V_W - V_RIGHT_PAD, y2: y, tx: V_LEFT_PAD - 4, ty: y + 3, label: Math.round(frac * maxVal) };
        });
    }

    // ── Line ───────────────────────────────────────────────────────────────────
    get lineViewBox() { return `0 0 ${V_W} ${V_H}`; }
    get lineBaseY()   { return this.vBaseY; }

    get linePoints() {
        if (!this.hasData) return [];
        const count  = this._data.length;
        const availW = V_W - V_LEFT_PAD - V_RIGHT_PAD;
        const availH = V_H - V_TOP_PAD - V_BOTTOM_PAD;
        const maxVal = Math.max(...this._data.map(d => d.value || 0), 1);
        const baseY  = this.vBaseY;
        return this._data.map((d, i) => {
            const cx       = count > 1 ? V_LEFT_PAD + (i / (count - 1)) * availW : V_LEFT_PAD + availW / 2;
            const cy       = baseY - ((d.value || 0) / maxVal) * availH;
            const rawLabel = d.label || '';
            const label    = rawLabel.length > 10 ? rawLabel.substring(0, 10) + '…' : rawLabel;
            return {
                id: i,
                cx, cy,
                value: d.value, rawLabel, label,
                lblX: cx, lblY: baseY + 6,
                lblTransform: `rotate(-45, ${cx}, ${baseY + 2})`,
                valX: cx, valY: cy - 7
            };
        });
    }

    get linePath() {
        const pts = this.linePoints;
        if (!pts || pts.length === 0) return '';
        if (pts.length === 1) return `M ${pts[0].cx} ${pts[0].cy}`;
        return pts.map((p, i) => (i === 0 ? `M ${p.cx} ${p.cy}` : `L ${p.cx} ${p.cy}`)).join(' ');
    }

    get lineAreaPath() {
        const pts = this.linePoints;
        if (!pts || pts.length === 0) return '';
        const baseY = this.lineBaseY;
        return `M ${pts[0].cx} ${baseY} ` + pts.map(p => `L ${p.cx} ${p.cy}`).join(' ') + ` L ${pts[pts.length - 1].cx} ${baseY} Z`;
    }

    get lineGridLines() { return this.vGridLines; }

    // ── Click ──────────────────────────────────────────────────────────────────
    handleBarClick(event) {
        const idx  = parseInt(event.currentTarget.dataset.idx, 10);
        let items;
        if (this.isVertical)  items = this.vBars;
        else if (this.isLine) items = this.linePoints;
        else                  items = this.hBars;
        const item = items[idx];
        if (!item) return;
        this.dispatchEvent(new CustomEvent('drilldown', {
            bubbles: true,
            detail: { dimension: this.dimension, value: item.rawLabel, count: item.value }
        }));
    }
}