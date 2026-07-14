import { LightningElement, api } from 'lwc';

function deepClone(obj) {
    return JSON.parse(JSON.stringify(obj || {}));
}

function buildOptionLabelMap(fields) {
    const map = {};
    (fields || []).forEach((f) => {
        if (f.type === 'multiselect') {
            map[f.key] = new Map((f.options || []).map((o) => [o.value, o.label]));
        }
    });
    return map;
}

export default class KenCustomAudienceGroup extends LightningElement {
    @api role;
    @api groupLabel = 'Custom Group 1';

    _config = { fields: [] };
    _selections = {};
    _computedConfig = { fields: [] };

    @api
    get config() {
        return this._computedConfig;
    }
    set config(v) {
        this._config = v || { fields: [] };
        this._recompute();
    }

    @api
    get selections() {
        return this._selections;
    }
    set selections(v) {
        this._selections = deepClone(v || {});
        this._recompute();
    }

    _recompute() {
        const cfg = this._config || { fields: [] };
        const fields = (cfg.fields || []).map((f) => ({
            ...f,
            isMulti: f.type === 'multiselect',
            isText: f.type === 'text',
            value: this._selections?.[f.key] ?? (f.type === 'multiselect' ? [] : '')
        }));
        this._computedConfig = { ...cfg, fields };
    }

    handleMultiChange(event) {
        const key = event.target.dataset.key;
        const value = event.detail.value;

        this._selections = { ...this._selections, [key]: Array.isArray(value) ? [...value] : [] };
        this._recompute();
        this.dispatchEvent(new CustomEvent('change', { detail: { selections: deepClone(this._selections) } }));
    }

    handleTextChange(event) {
        const key = event.target.dataset.key;
        const value = event.target.value;

        this._selections = { ...this._selections, [key]: value || '' };
        this._recompute();
        this.dispatchEvent(new CustomEvent('change', { detail: { selections: deepClone(this._selections) } }));
    }

    handleSave(event) {
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }
        const cfg = this._config || { fields: [] };
        const labelMaps = buildOptionLabelMap(cfg.fields);

        const parts = (cfg.fields || []).map((f) => {
            const rawVal = this._selections?.[f.key];

            if (f.type === 'multiselect') {
                const vals = Array.isArray(rawVal) ? rawVal : [];
                const lm = labelMaps[f.key];
                const labelVals = vals.map((x) => (lm && lm.get(x) ? lm.get(x) : x));
                return `${f.label}: ${labelVals.length ? labelVals.join(', ') : '—'}`;
            }

            if (f.type === 'text') {
                return `${f.label}: ${rawVal ? rawVal : '—'}`;
            }

            return `${f.label}: —`;
        });

        const summary = parts.join(' • ');
        this.dispatchEvent(
            new CustomEvent('groupsave', {
                detail: { role: this.role, selections: deepClone(this._selections), summary }
            })
        );
    }
}