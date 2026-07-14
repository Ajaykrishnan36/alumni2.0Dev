import { LightningElement, api } from 'lwc';

export default class KenEventStepScheduleV2 extends LightningElement {
    @api startDate = '';
    @api endDate = '';
    @api startTime = '';
    @api endTime = '';
    @api multiDay = false;
    // Persisted per-day speaker structure from the wizard: [{ date, speakers:[name,...] }, ...]
    @api daySchedules = [];

    // Draft speaker-name input keyed by date (component-local, not persisted until "Add").
    _drafts = {};

    get switchClass() {
        return this.multiDay ? 'switch switch--on' : 'switch';
    }

    // Today as YYYY-MM-DD — Start Date cannot be in the past.
    get todayStr() {
        const d = new Date();
        const m = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${d.getFullYear()}-${m}-${day}`;
    }
    // End Date cannot be before the chosen Start Date (falls back to today).
    get endMinDate() {
        return this.startDate || this.todayStr;
    }

    // Show the per-day breakdown only when multi-day is ON and both dates are set & valid.
    get showDayBreakdown() {
        return this.multiDay && this.startDate && this.endDate && this._dateList().length > 0;
    }
    // Multi-day is ON but the date range isn't set yet — prompt the host so the
    // area under the toggle is never just blank.
    get multiDayNeedsDates() {
        return this.multiDay && !(this.startDate && this.endDate && this._dateList().length > 0);
    }

    // Render rows: one per calendar day (start..end inclusive) with its speaker chips.
    get dayRows() {
        const saved = this._savedMap();
        return this._dateList().map((date, i) => {
            const speakers = saved[date] || [];
            return {
                date,
                label: `Day ${i + 1} · ${this._prettyDate(date)}`,
                speakers: speakers.map((name, si) => ({ key: `${date}-${si}`, name })),
                hasSpeakers: speakers.length > 0,
                draft: this._drafts[date] || ''
            };
        });
    }

    // ---- helpers ----
    _dateList() {
        const out = [];
        if (!this.startDate || !this.endDate) return out;
        const start = this._parse(this.startDate);
        const end = this._parse(this.endDate);
        if (!start || !end || end < start) return out;
        // Cap at 60 days to avoid runaway loops on bad input.
        let cur = new Date(start);
        let guard = 0;
        while (cur <= end && guard < 60) {
            out.push(this._fmt(cur));
            cur.setDate(cur.getDate() + 1);
            guard += 1;
        }
        return out;
    }
    _parse(s) {
        const [y, m, d] = String(s).split('-').map(Number);
        if (!y || !m || !d) return null;
        return new Date(y, m - 1, d);
    }
    _fmt(d) {
        const m = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${d.getFullYear()}-${m}-${day}`;
    }
    _prettyDate(s) {
        const d = this._parse(s);
        if (!d) return s;
        return d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
    }
    _savedMap() {
        const map = {};
        (this.daySchedules || []).forEach(ds => {
            if (ds && ds.date) map[ds.date] = Array.isArray(ds.speakers) ? ds.speakers : [];
        });
        return map;
    }

    handleInput(event) {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: event.currentTarget.dataset.field, value: event.target.value }
        }));
    }
    handleToggleMultiDay() {
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: 'multiDay', value: !this.multiDay }
        }));
    }

    handleDraftInput(event) {
        const date = event.currentTarget.dataset.date;
        this._drafts = { ...this._drafts, [date]: event.target.value };
    }
    handleDraftKey(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this._addSpeaker(event.currentTarget.dataset.date);
        }
    }
    handleAddSpeaker(event) {
        this._addSpeaker(event.currentTarget.dataset.date);
    }
    _addSpeaker(date) {
        const name = (this._drafts[date] || '').trim();
        if (!name) return;
        const map = this._savedMap();
        const existing = map[date] || [];
        if (existing.some(n => n.toLowerCase() === name.toLowerCase())) {
            this._drafts = { ...this._drafts, [date]: '' };
            return;
        }
        map[date] = [...existing, name];
        this._drafts = { ...this._drafts, [date]: '' };
        this._emitDaySchedules(map);
    }
    handleRemoveSpeaker(event) {
        const { date, name } = event.currentTarget.dataset;
        const map = this._savedMap();
        map[date] = (map[date] || []).filter(n => n !== name);
        this._emitDaySchedules(map);
    }

    // Re-emit the full daySchedules array (only days within the current range that have speakers).
    _emitDaySchedules(map) {
        const days = this._dateList().map(date => ({ date, speakers: map[date] || [] }));
        this.dispatchEvent(new CustomEvent('valuechange', {
            detail: { field: 'daySchedules', value: days }
        }));
    }
}