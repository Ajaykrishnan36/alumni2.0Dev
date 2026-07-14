import { LightningElement, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import LEAFLET_JS from '@salesforce/resourceUrl/kenLeafletJs';
import WORLD_GEO from '@salesforce/resourceUrl/kenWorldGeo';
import GEO_DATA from '@salesforce/resourceUrl/kenGeoData';
import getAlumniLocationCounts from '@salesforce/apex/KenAlumniMapController.getAlumniLocationCounts';

const COUNTRY_MAX_ZOOM = 3;
const STATE_MAX_ZOOM = 5;
const STATE_VIEW_ZOOM = 5;
const CITY_VIEW_ZOOM = 7;
const PIN_THRESHOLD = 10;

export default class KenAlumniMap extends LightningElement {
    @api title = 'Our Global Alumni Community';
    @api mapHeight = 560;
    @api hideHeader = false;

    isLoading = true;
    errorMessage = '';
    errorDetail = '';
    summaryLabel = '';

    map;
    bubbleLayer;
    labelLayer;
    currentLevel;
    countryNodes = [];
    stateLevelNodes = [];
    cityLevelNodes = [];
    countryLabels = [];
    stateLabels = [];
    cityLabels = [];
    hasStarted = false;
    resizeObserver;

    get showHeader() {
        return !(this.hideHeader === true || this.hideHeader === 'true');
    }

    get shellStyle() {
        const h = parseInt(this.mapHeight, 10) || 560;
        return `height:${h}px`;
    }

    renderedCallback() {
        if (this.hasStarted) {
            return;
        }
        this.hasStarted = true;
        this.initialize();
    }

    disconnectedCallback() {
        if (this.resizeObserver) {
            this.resizeObserver.disconnect();
            this.resizeObserver = undefined;
        }
        if (this.map) {
            this.map.remove();
            this.map = undefined;
        }
        this.hasStarted = false;
    }

    async initialize() {
        try {
            const [, worldGeo, geoData, rows] = await Promise.all([
                loadScript(this, LEAFLET_JS),
                this.fetchJson(WORLD_GEO),
                this.fetchJson(GEO_DATA),
                getAlumniLocationCounts()
            ]);
            this.buildNodes(rows || [], geoData);
            this.countryLabels = geoData.countryLabels || [];
            this.cityLabels = geoData.cityLabels || [];
            this.stateLabels = worldGeo.stateLabels || [];
            this.renderMap(worldGeo);
            this.isLoading = false;
        } catch (e) {
            this.isLoading = false;
            this.errorMessage = 'The alumni map could not be loaded right now. Please try again later.';
            this.errorDetail = (e && (e.message || (e.body && e.body.message))) || String(e);
            console.error('kenAlumniMap failed to initialize', e);
        }
    }

    async fetchJson(url) {
        const res = await fetch(url);
        if (!res.ok) {
            throw new Error(`Map data request failed with status ${res.status}`);
        }
        return res.json();
    }

    normalizeKey(value) {
        return String(value || '')
            .toLowerCase()
            .normalize('NFD')
            .replace(/[̀-ͯ]/g, '')
            .replace(/[^a-z0-9 ]+/g, ' ')
            .replace(/\s+/g, ' ')
            .trim();
    }

    buildNodes(rows, geo) {
        const countries = new Map();
        const states = new Map();
        const cities = new Map();
        let grandTotal = 0;

        rows.forEach((row) => {
            const total = row.total || 0;
            grandTotal += total;
            const cityKey = this.normalizeKey(row.city);
            let iso = geo.countries[this.normalizeKey(row.country)];
            if (!iso && cityKey && geo.cities.IN && geo.cities.IN[cityKey]) {
                iso = 'IN';
            }
            if (!iso) {
                return;
            }
            const cityCoords = cityKey && geo.cities[iso] ? geo.cities[iso][cityKey] : undefined;

            let country = countries.get(iso);
            if (!country) {
                country = { name: row.country, count: 0, latW: 0, lngW: 0, wSum: 0, center: geo.centers[iso] };
                countries.set(iso, country);
            }
            country.count += total;
            if (!country.name && row.country) {
                country.name = row.country;
            }
            if (cityCoords) {
                country.latW += cityCoords[0] * total;
                country.lngW += cityCoords[1] * total;
                country.wSum += total;
            }

            const stateKey = this.normalizeKey(row.state);
            if (stateKey) {
                const sk = `${iso}|${stateKey}`;
                let state = states.get(sk);
                if (!state) {
                    state = { iso, name: row.state, count: 0, latW: 0, lngW: 0, wSum: 0 };
                    states.set(sk, state);
                }
                state.count += total;
                if (cityCoords) {
                    state.latW += cityCoords[0] * total;
                    state.lngW += cityCoords[1] * total;
                    state.wSum += total;
                }
            }

            if (cityCoords) {
                const ck = `${iso}|${cityKey}`;
                let city = cities.get(ck);
                if (!city) {
                    city = { iso, name: row.city, count: 0, pos: [cityCoords[0], cityCoords[1]] };
                    cities.set(ck, city);
                }
                city.count += total;
            }
        });

        const countryNodes = [];
        const countryPos = new Map();
        countries.forEach((c, iso) => {
            const pos = c.wSum > 0 ? [c.latW / c.wSum, c.lngW / c.wSum] : c.center;
            if (!pos) {
                return;
            }
            countryPos.set(iso, pos);
            countryNodes.push({ name: c.name || iso, count: c.count, pos, drillZoom: STATE_VIEW_ZOOM });
        });
        this.countryNodes = countryNodes;

        const placedStateTotals = new Map();
        const stateNodes = [];
        states.forEach((s) => {
            if (s.wSum <= 0) {
                return;
            }
            stateNodes.push({
                name: s.name,
                count: s.count,
                pos: [s.latW / s.wSum, s.lngW / s.wSum],
                drillZoom: CITY_VIEW_ZOOM
            });
            placedStateTotals.set(s.iso, (placedStateTotals.get(s.iso) || 0) + s.count);
        });
        this.stateLevelNodes = stateNodes.concat(
            this.buildRemainderNodes(countries, countryPos, placedStateTotals, STATE_VIEW_ZOOM)
        );

        const placedCityTotals = new Map();
        const cityNodes = [];
        cities.forEach((c) => {
            cityNodes.push({ name: c.name, count: c.count, pos: c.pos, drillZoom: null });
            placedCityTotals.set(c.iso, (placedCityTotals.get(c.iso) || 0) + c.count);
        });
        this.cityLevelNodes = cityNodes.concat(
            this.buildRemainderNodes(countries, countryPos, placedCityTotals, null)
        );

        const countryCount = countryNodes.length;
        this.summaryLabel = `${grandTotal.toLocaleString('en-IN')} alumni across ${countryCount} ${
            countryCount === 1 ? 'country' : 'countries'
        }`;
    }

    buildRemainderNodes(countries, countryPos, placedTotals, drillZoom) {
        const nodes = [];
        countries.forEach((c, iso) => {
            const pos = countryPos.get(iso);
            if (!pos) {
                return;
            }
            const placed = placedTotals.get(iso) || 0;
            const remainder = c.count - placed;
            if (remainder <= 0) {
                return;
            }
            const name = placed > 0 ? `${c.name || iso} · other locations` : c.name || iso;
            nodes.push({ name, count: remainder, pos, drillZoom });
        });
        return nodes;
    }

    renderMap(worldGeo) {
        const container = this.template.querySelector('.map-container');
        const L = window.L;
        this.map = L.map(container, {
            attributionControl: false,
            minZoom: 2,
            maxZoom: 9,
            zoomSnap: 0.5,
            worldCopyJump: true,
            maxBounds: [
                [-65, -200],
                [82, 200]
            ],
            maxBoundsViscosity: 0.8
        });

        L.geoJSON(worldGeo.world, {
            style: () => ({ fillColor: '#ffffff', fillOpacity: 1, color: '#d2d3d8', weight: 0.8 })
        }).addTo(this.map);
        L.geoJSON(worldGeo.states, {
            style: () => ({ fill: false, color: '#d2d3d8', weight: 0.7 })
        }).addTo(this.map);

        try {
            const labelPane = this.map.createPane('kenLabels');
            labelPane.style.zIndex = 450;
            labelPane.style.pointerEvents = 'none';
            this.labelLayer = L.layerGroup().addTo(this.map);
        } catch (e) {
            this.labelLayer = undefined;
            console.error('kenAlumniMap label pane setup failed', e);
        }
        this.bubbleLayer = L.layerGroup().addTo(this.map);
        this.map.on('zoomend', () => {
            this.syncLevel();
            this.renderLabels();
        });
        this.map.on('moveend', () => this.renderLabels());

        if (this.countryNodes.length) {
            this.map.fitBounds(L.latLngBounds(this.countryNodes.map((n) => n.pos)), {
                padding: [40, 40],
                maxZoom: 4
            });
        } else {
            this.map.setView([20, 40], 2);
        }
        this.syncLevel();
        this.renderLabels();
        this.observeResize();
    }

    observeResize() {
        const shell = this.template.querySelector('.map-shell');
        if (typeof ResizeObserver === 'function' && shell) {
            this.resizeObserver = new ResizeObserver(() => {
                if (this.map) {
                    this.map.invalidateSize();
                }
            });
            this.resizeObserver.observe(shell);
        }
    }

    syncLevel() {
        if (!this.map) {
            return;
        }
        const zoom = this.map.getZoom();
        const level = zoom <= COUNTRY_MAX_ZOOM ? 'country' : zoom <= STATE_MAX_ZOOM ? 'state' : 'city';
        if (level !== this.currentLevel) {
            this.currentLevel = level;
            this.drawBubbles(level);
        }
    }

    renderLabels() {
        try {
            this.renderLabelsUnsafe();
        } catch (e) {
            console.error('kenAlumniMap label rendering failed', e);
        }
    }

    renderLabelsUnsafe() {
        if (!this.map || !this.labelLayer) {
            return;
        }
        this.labelLayer.clearLayers();
        const zoom = this.map.getZoom();
        const bounds = this.map.getBounds().pad(0.15);
        const inView = (lat, lng) => bounds.contains([lat, lng]);

        this.countryLabels.forEach(([name, lat, lng]) => {
            if (inView(lat, lng)) {
                this.addLabel(name, [lat, lng], 'map-label-country');
            }
        });
        if (zoom >= 4.5) {
            this.stateLabels.forEach(([name, lat, lng]) => {
                if (inView(lat, lng)) {
                    this.addLabel(name, [lat, lng], 'map-label-state');
                }
            });
            const maxTier = zoom >= 7 ? 3 : zoom >= 6 ? 2 : 1;
            const visible = [];
            this.cityLabels.forEach(([name, lat, lng, tier]) => {
                if (tier <= maxTier && inView(lat, lng)) {
                    visible.push([name, lat, lng, tier]);
                }
            });
            visible.sort((a, b) => a[3] - b[3]);
            visible.slice(0, 140).forEach(([name, lat, lng]) => {
                this.addLabel(name, [lat, lng], 'map-label-city', true);
            });
        }
    }

    addLabel(name, pos, className, withDot) {
        const L = window.L;
        const dot = withDot ? '<span class="map-place-dot"></span>' : '';
        const html = `<div class="map-place-label ${className}">${dot}<span>${this.escapeHtml(name)}</span></div>`;
        const marker = L.marker(pos, {
            pane: 'kenLabels',
            interactive: false,
            keyboard: false,
            icon: L.divIcon({ className: 'ken-map-icon', html, iconSize: [0, 0], iconAnchor: [0, 0] })
        });
        this.labelLayer.addLayer(marker);
    }

    escapeHtml(value) {
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    drawBubbles(level) {
        this.bubbleLayer.clearLayers();
        const nodes =
            level === 'country' ? this.countryNodes : level === 'state' ? this.stateLevelNodes : this.cityLevelNodes;
        if (!nodes.length) {
            return;
        }
        const max = nodes.reduce((m, n) => Math.max(m, n.count), 1);
        nodes.forEach((n) => {
            const marker = window.L.marker(n.pos, { icon: this.buildIcon(n.count, max), keyboard: false });
            const tip = document.createElement('span');
            tip.textContent = `${n.name} · ${n.count.toLocaleString('en-IN')} alumni`;
            marker.bindTooltip(tip, { direction: 'top', offset: [0, -8], opacity: 0.95 });
            if (n.drillZoom) {
                marker.on('click', () => this.map.flyTo(n.pos, n.drillZoom, { duration: 0.8 }));
            }
            this.bubbleLayer.addLayer(marker);
        });
    }

    buildIcon(count, max) {
        const L = window.L;
        if (count < PIN_THRESHOLD) {
            return L.divIcon({
                className: 'ken-map-icon',
                html: `<div class="map-pin"><span class="map-pin-dot"></span>${count}</div>`,
                iconSize: [46, 34],
                iconAnchor: [12, 34]
            });
        }
        const size = Math.min(78, 34 + Math.round(42 * Math.sqrt(count / max)));
        const fontSize = size >= 62 ? 15 : size >= 48 ? 13 : 12;
        return L.divIcon({
            className: 'ken-map-icon',
            html: `<div class="map-bubble" style="width:${size}px;height:${size}px;font-size:${fontSize}px">${count}</div>`,
            iconSize: [size, size],
            iconAnchor: [size / 2, size / 2]
        });
    }
}