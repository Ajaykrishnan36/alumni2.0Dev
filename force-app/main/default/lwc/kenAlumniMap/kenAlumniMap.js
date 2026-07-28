import { LightningElement, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import LEAFLET_JS from '@salesforce/resourceUrl/kenLeafletJs';
import GEO_DATA from '@salesforce/resourceUrl/kenGeoData';
import INDIA_BOUNDARY_JS from '@salesforce/resourceUrl/kenIndiaBoundaryJs';
import getAlumniLocationCounts from '@salesforce/apex/KenAlumniMapController.getAlumniLocationCounts';
import getAlumniAtLocation from '@salesforce/apex/KenAlumniMapController.getAlumniAtLocation';

const COUNTRY_MAX_ZOOM = 3;
const STATE_MAX_ZOOM = 5;
const STATE_VIEW_ZOOM = 5;
const CITY_VIEW_ZOOM = 7;

// CARTO Voyager, not standard OpenStreetMap: OSM's raster tiles carry
// local-language labels (Chinese, Urdu, Devanagari, Burmese...) baked into the
// image, while CARTO renders Latin/English names worldwide. Voyager is CARTO's
// coloured style; light_all is the plainer Positron alternative and both share
// the cartodb-light boundary config.
const BASE_TILE_URL = 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
const BASE_ATTRIBUTION =
    '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> contributors, &copy; <a href="https://carto.com/attributions" target="_blank" rel="noopener">CARTO</a>';
const BASE_LAYER_CONFIG = 'cartodb-light';
const TILE_MAX_ZOOM = 12;
// Correction geometry only exists along India's international borders — the
// Kashmir/Ladakh sector, the Himalayan arc, the north-east and the Sir Creek
// end of the Pakistan border. Tiles outside this envelope are served as plain
// images, because the corrected layer has to fetch, decode, canvas-repaint and
// re-encode every tile it handles — doing that worldwide is what made zooming
// lag. Peninsular India (below ~22N) needs no corrections, so the southern
// cities where alumni actually cluster stay on the fast path.
const CORRECTION_REGION = { south: 22, west: 67, north: 37.7, east: 97.8 };
// Keep tile churn down while the user is actively zooming/panning.
const TILE_PERF_OPTIONS = {
    updateWhenIdle: true,
    updateWhenZooming: false,
    keepBuffer: 1
};
// Corrected tiles are expensive to build (decode -> canvas repaint -> re-encode)
// and the library rebuilds them on every tile creation, so zooming in and out
// over Kashmir redid the same work each time. Hold the finished bytes so a
// revisited tile is just an object URL. Bounded, FIFO-evicted.
const CORRECTED_TILE_CACHE_LIMIT = 400;
// The library keeps ONE OffscreenCanvas per TileFixer and awaits convertToBlob
// on it, so concurrent tiles can repaint the canvas mid-encode and land each
// other's pixels in the wrong tile. TileFixer instances are keyed by pmtilesUrl,
// so a URL fragment (never sent to the server, shares the HTTP cache entry)
// yields independent instances to round-robin over.
const FIXER_POOL_SIZE = 4;
// Ceiling on how many next-zoom tiles are built ahead of time per idle pass.
const WARM_TILE_LIMIT = 12;
const LEVEL_RANK = { country: 0, state: 1, city: 2 };
const SPLIT_ANIMATION_MS = 460;
// The boundary corrector resolves this itself from its own script URL, which
// under LWR points at a Salesforce static-resource path that holds no data —
// so it must always be passed explicitly.
const PMTILES_URL =
    'https://cdn.jsdelivr.net/npm/@india-boundary-corrector/data@0.2.2/india_boundary_corrections.pmtiles.gz';
const CORRECTED_TILE_ERROR_LIMIT = 4;

export default class KenAlumniMap extends LightningElement {
    @api title = 'Our Global Alumni Community';
    @api mapHeight = 560;
    @api hideHeader = false;
    // 'guest' (landing page — shows a login/register prompt instead of people),
    // 'portal' (community — profile click opens the network detail view),
    // 'admin' (backend — profile click opens the Alumni 360).
    @api context = 'portal';

    isLoading = true;
    errorMessage = '';
    errorDetail = '';
    summaryLabel = '';

    sidebarOpen = false;
    sidebarTitle = '';
    sidebarCount = 0;
    sidebarPeople = [];
    sidebarLoading = false;
    sidebarError = '';

    map;
    bubbleLayer;
    tileLayer;
    currentLevel;
    countryNodes = [];
    stateLevelNodes = [];
    cityLevelNodes = [];
    hasStarted = false;
    resizeObserver;

    get showHeader() {
        return !(this.hideHeader === true || this.hideHeader === 'true');
    }

    get shellStyle() {
        const h = parseInt(this.mapHeight, 10) || 560;
        return `height:${h}px`;
    }

    get isGuest() {
        return this.context === 'guest';
    }

    get showGuestPrompt() {
        return this.sidebarOpen && this.isGuest;
    }

    get showPeopleSidebar() {
        return this.sidebarOpen && !this.isGuest;
    }

    get sidebarCountLabel() {
        const c = this.sidebarCount || 0;
        return `${c.toLocaleString('en-IN')} ${c === 1 ? 'alumnus' : 'alumni'}`;
    }

    get hasPeople() {
        return this.sidebarPeople && this.sidebarPeople.length > 0;
    }

    get showEmptyState() {
        return this.sidebarOpen && !this.isGuest && !this.sidebarLoading && !this.sidebarError && !this.hasPeople;
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
        this.tileLayer = undefined;
        this.hasStarted = false;
    }

    async initialize() {
        try {
            const [, , rows] = await Promise.all([
                loadScript(this, LEAFLET_JS),
                loadScript(this, GEO_DATA),
                getAlumniLocationCounts(),
                loadScript(this, INDIA_BOUNDARY_JS).catch((e) => {
                    console.warn('kenAlumniMap: India boundary corrector did not load', e);
                })
            ]);
            const geoData = window.KEN_GEO_DATA;
            if (!geoData) {
                throw new Error('Map data scripts did not load');
            }
            this.buildNodes(rows || [], geoData);
            this.renderMap();
            this.isLoading = false;
        } catch (e) {
            this.isLoading = false;
            this.errorMessage = 'The alumni map could not be loaded right now. Please try again later.';
            this.errorDetail = (e && (e.message || (e.body && e.body.message))) || String(e);
            console.error('kenAlumniMap failed to initialize', e);
        }
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

    computeInitials(name) {
        const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
        if (!parts.length) {
            return '?';
        }
        const first = parts[0][0] || '';
        const last = parts.length > 1 ? parts[parts.length - 1][0] || '' : '';
        return (first + last).toUpperCase();
    }

    buildNodes(rows, geo) {
        const countries = new Map();
        const states = new Map();
        const cities = new Map();
        let grandTotal = 0;

        rows.forEach((row) => {
            const total = row.total || 0;
            const cityKey = this.normalizeKey(row.city);
            let iso = geo.countries[this.normalizeKey(row.country)];
            if (!iso && cityKey && geo.cities.IN && geo.cities.IN[cityKey]) {
                iso = 'IN';
            }
            if (!iso) {
                return;
            }
            const cityCoords = cityKey && geo.cities[iso] ? geo.cities[iso][cityKey] : undefined;
            if (!cityCoords) {
                // City name doesn't match a recognized place — exclude from every
                // count and every zoom level rather than guessing a position.
                return;
            }

            grandTotal += total;

            let country = countries.get(iso);
            if (!country) {
                country = {
                    name: row.country,
                    count: 0,
                    latW: 0,
                    lngW: 0,
                    wSum: 0,
                    cityKeys: new Set(),
                    cities: new Set(),
                    countries: new Set()
                };
                countries.set(iso, country);
            }
            country.count += total;
            if (!country.name && row.country) {
                country.name = row.country;
            }
            country.latW += cityCoords[0] * total;
            country.lngW += cityCoords[1] * total;
            country.wSum += total;
            country.cityKeys.add(cityKey);
            if (row.city) country.cities.add(row.city);
            if (row.country) country.countries.add(row.country);

            const stateKey = this.normalizeKey(row.state);
            if (stateKey) {
                const sk = `${iso}|${stateKey}`;
                let state = states.get(sk);
                if (!state) {
                    state = {
                        iso,
                        name: row.state,
                        count: 0,
                        latW: 0,
                        lngW: 0,
                        wSum: 0,
                        cityKeys: new Set(),
                        cities: new Set(),
                        countries: new Set()
                    };
                    states.set(sk, state);
                }
                state.count += total;
                state.latW += cityCoords[0] * total;
                state.lngW += cityCoords[1] * total;
                state.wSum += total;
                state.cityKeys.add(cityKey);
                if (row.city) state.cities.add(row.city);
                if (row.country) state.countries.add(row.country);
            }

            const ck = `${iso}|${cityKey}`;
            let city = cities.get(ck);
            if (!city) {
                city = {
                    iso,
                    name: row.city,
                    count: 0,
                    pos: [cityCoords[0], cityCoords[1]],
                    cities: new Set(),
                    countries: new Set()
                };
                cities.set(ck, city);
            }
            city.count += total;
            if (row.city) {
                city.cities.add(row.city);
            }
            if (row.country) {
                city.countries.add(row.country);
            }
        });

        const countryNodes = [];
        countries.forEach((c, iso) => {
            const pos = [c.latW / c.wSum, c.lngW / c.wSum];
            countryNodes.push({
                name: c.name || iso,
                count: c.count,
                pos,
                drillZoom: STATE_VIEW_ZOOM,
                // Terminal = everyone here is in one place, so zooming can't split it.
                isTerminal: c.cityKeys.size <= 1,
                cities: Array.from(c.cities),
                countries: Array.from(c.countries)
            });
        });
        this.countryNodes = countryNodes;

        // Merge state-level groups by real-world distance, not state-name text —
        // inconsistent spelling/typos in the source data ("Tamilnadu" vs
        // "Tamil Nadu" vs "Tamin nadu") would otherwise render as multiple
        // overlapping bubbles for what is really the same place. A plain
        // position match isn't enough: a group whose members are a genuine mix
        // of two nearby cities lands at a slightly different point than a
        // group that's 100% one of those cities, so we cluster within a
        // radius instead of requiring an exact match.
        const STATE_CLUSTER_RADIUS_KM = 150;
        const toRad = (deg) => (deg * Math.PI) / 180;
        const haversineKm = (a, b) => {
            const R = 6371;
            const dLat = toRad(b[0] - a[0]);
            const dLon = toRad(b[1] - a[1]);
            const h =
                Math.sin(dLat / 2) ** 2 +
                Math.cos(toRad(a[0])) * Math.cos(toRad(b[0])) * Math.sin(dLon / 2) ** 2;
            return 2 * R * Math.asin(Math.sqrt(h));
        };

        const stateClusters = [];
        states.forEach((s) => {
            const pos = [s.latW / s.wSum, s.lngW / s.wSum];
            const cluster = stateClusters.find((cl) => haversineKm(cl.pos, pos) <= STATE_CLUSTER_RADIUS_KM);
            if (cluster) {
                cluster.latW += s.latW;
                cluster.lngW += s.lngW;
                cluster.wSum += s.wSum;
                cluster.count += s.count;
                cluster.pos = [cluster.latW / cluster.wSum, cluster.lngW / cluster.wSum];
                s.cityKeys.forEach((k) => cluster.cityKeys.add(k));
                s.cities.forEach((k) => cluster.cities.add(k));
                s.countries.forEach((k) => cluster.countries.add(k));
            } else {
                stateClusters.push({
                    name: s.name,
                    count: s.count,
                    latW: s.latW,
                    lngW: s.lngW,
                    wSum: s.wSum,
                    pos,
                    cityKeys: new Set(s.cityKeys),
                    cities: new Set(s.cities),
                    countries: new Set(s.countries)
                });
            }
        });
        this.stateLevelNodes = stateClusters.map((cl) => ({
            name: cl.name,
            count: cl.count,
            pos: cl.pos,
            drillZoom: CITY_VIEW_ZOOM,
            isTerminal: cl.cityKeys.size <= 1,
            cities: Array.from(cl.cities),
            countries: Array.from(cl.countries)
        }));

        const cityNodes = [];
        cities.forEach((c) => {
            cityNodes.push({
                name: c.name,
                count: c.count,
                pos: c.pos,
                drillZoom: null,
                isTerminal: true,
                cities: Array.from(c.cities),
                countries: Array.from(c.countries)
            });
        });
        this.cityLevelNodes = cityNodes;

        const countryCount = countryNodes.length;
        this.summaryLabel = `${grandTotal.toLocaleString('en-IN')} alumni across ${countryCount} ${
            countryCount === 1 ? 'country' : 'countries'
        }`;
    }

    renderMap() {
        const container = this.template.querySelector('.map-container');
        const L = window.L;
        this.map = L.map(container, {
            attributionControl: true,
            minZoom: 2,
            maxZoom: TILE_MAX_ZOOM,
            // Whole-level snapping: half-steps made Leaflet rebuild the tile set
            // twice per zoom level, doubling correction work over Kashmir.
            zoomSnap: 1,
            worldCopyJump: true,
            maxBounds: [
                [-65, -200],
                [82, 200]
            ],
            maxBoundsViscosity: 0.8
        });
        this.map.attributionControl.setPrefix('');
        this.setupBaseLayer();

        this.bubbleLayer = L.layerGroup().addTo(this.map);
        this.map.on('zoomend', () => {
            this.syncLevel();
            this.warmNextZoom();
        });
        this.map.on('moveend', () => this.warmNextZoom());

        if (this.countryNodes.length) {
            this.map.fitBounds(L.latLngBounds(this.countryNodes.map((n) => n.pos)), {
                padding: [40, 40],
                maxZoom: 4
            });
        } else {
            this.map.setView([20, 40], 2);
        }
        this.syncLevel();
        this.observeResize();
    }

    /**
     * Adds the basemap, preferring the India-boundary-corrected tile layer so
     * Jammu & Kashmir / Ladakh render per the Indian government depiction
     * instead of the raw OSM "on the ground" one. That layer fetches each tile
     * and repaints the boundaries onto it, so it needs connect-src CSP for the
     * tile host plus the PMTiles corrections host. If the extension is missing
     * or its tiles never load, the plain layer takes over.
     *
     * maxZoom stays capped at 9 (not the provider's native max) — this map is
     * an aggregate country/state/city clustering view, not street-level.
     */
    setupBaseLayer() {
        const L = window.L;
        const corrector = this.resolveCorrector();

        if (!corrector) {
            console.warn(
                'kenAlumniMap: IndiaBoundaryCorrector global not found after loadScript — using uncorrected basemap'
            );
        }

        if (corrector && typeof corrector.extendLeaflet === 'function') {
            try {
                corrector.extendLeaflet(L);
                const corrected = this.buildCorrectedLayer(L);
                this.watchCorrectedLayer(corrected);
                this.tileLayer = corrected;
                this.tileLayer.addTo(this.map);
                return;
            } catch (e) {
                console.warn('kenAlumniMap: corrected basemap unavailable, using uncorrected tiles', e);
            }
        }
        this.addPlainBaseLayer();
    }

    /**
     * Builds a corrected tile layer that only pays the correction cost for
     * tiles overlapping CORRECTION_REGION; everywhere else it falls back to
     * Leaflet's native img.src path, which the browser caches and decodes off
     * the main thread.
     */
    buildCorrectedLayer(L) {
        const Corrected = L.TileLayer.IndiaBoundaryCorrected;
        const region = L.latLngBounds(
            L.latLng(CORRECTION_REGION.south, CORRECTION_REGION.west),
            L.latLng(CORRECTION_REGION.north, CORRECTION_REGION.east)
        );
        const cache = new Map();
        const fixerPool = [];
        for (let i = 0; i < FIXER_POOL_SIZE; i += 1) {
            const probe = new Corrected(BASE_TILE_URL, {
                pmtilesUrl: `${PMTILES_URL}#pool${i}`,
                layerConfig: BASE_LAYER_CONFIG
            });
            fixerPool.push(probe.getTileFixer());
        }
        let nextFixer = 0;

        const Hybrid = Corrected.extend({
            createTile: function (coords, done) {
                if (!this._tileCoordsToBounds(coords).intersects(region)) {
                    return L.TileLayer.prototype.createTile.call(this, coords, done);
                }

                const layerConfig = this.getLayerConfig();
                if (!layerConfig) {
                    return L.TileLayer.prototype.createTile.call(this, coords, done);
                }

                const tile = document.createElement('img');
                tile.alt = '';
                const key = `${coords.z}/${coords.x}/${coords.y}`;
                const cached = cache.get(key);
                if (cached) {
                    this._paintTile(tile, cached, done);
                    return tile;
                }

                const controller = new AbortController();
                tile.cancel = () => controller.abort();

                const fixer = fixerPool[nextFixer % fixerPool.length] || this.getTileFixer();
                nextFixer += 1;

                fixer
                    .fetchAndFixTile(
                        this.getTileUrl(coords),
                        coords.z,
                        coords.x,
                        coords.y,
                        layerConfig,
                        { signal: controller.signal },
                        this.options.fallbackOnCorrectionFailure
                    )
                    .then(({ data, correctionsFailed, correctionsError }) => {
                        if (correctionsFailed) {
                            this.fire('correctionerror', {
                                error: correctionsError,
                                coords: { z: coords.z, x: coords.x, y: coords.y },
                                tileUrl: this.getTileUrl(coords)
                            });
                        }
                        const blob = new Blob([data]);
                        if (cache.size >= CORRECTED_TILE_CACHE_LIMIT) {
                            cache.delete(cache.keys().next().value);
                        }
                        cache.set(key, blob);
                        tile.cancel = undefined;
                        this._paintTile(tile, blob, done);
                    })
                    .catch((err) => {
                        if (err && err.name !== 'AbortError') {
                            console.warn('kenAlumniMap: corrected tile failed', err);
                            done(err, tile);
                        }
                    });

                return tile;
            },

            /**
             * Builds the corrected tiles for `zoom` over the current viewport
             * ahead of time, during browser idle, so zooming into the border
             * belt hits the cache instead of blocking on decode + median blur +
             * re-encode. Bounded per pass so idle work stays short.
             */
            warmZoom: function (zoom) {
                const map = this._map;
                if (!map || zoom > this.options.maxZoom || !this.getLayerConfig()) {
                    return;
                }
                const bounds = map.getBounds();
                const nw = map.project(bounds.getNorthWest(), zoom).divideBy(256).floor();
                const se = map.project(bounds.getSouthEast(), zoom).divideBy(256).floor();
                const pending = [];
                for (let x = nw.x; x <= se.x && pending.length < WARM_TILE_LIMIT; x += 1) {
                    for (let y = nw.y; y <= se.y && pending.length < WARM_TILE_LIMIT; y += 1) {
                        const coords = new L.Point(x, y);
                        coords.z = zoom;
                        if (cache.has(`${zoom}/${x}/${y}`)) {
                            continue;
                        }
                        if (!this._tileCoordsToBounds(coords).intersects(region)) {
                            continue;
                        }
                        pending.push(coords);
                    }
                }
                pending.forEach((coords) => this._warmTile(coords));
            },

            _warmTile: function (coords) {
                const key = `${coords.z}/${coords.x}/${coords.y}`;
                const fixer = fixerPool[nextFixer % fixerPool.length];
                nextFixer += 1;
                const run = () =>
                    fixer
                        .fetchAndFixTile(
                            this.getTileUrl(coords),
                            coords.z,
                            coords.x,
                            coords.y,
                            this.getLayerConfig(),
                            {},
                            true
                        )
                        .then(({ data }) => {
                            if (cache.has(key)) {
                                return;
                            }
                            if (cache.size >= CORRECTED_TILE_CACHE_LIMIT) {
                                cache.delete(cache.keys().next().value);
                            }
                            cache.set(key, new Blob([data]));
                        })
                        .catch(() => {
                            /* prefetch is best-effort */
                        });
                if (typeof window.requestIdleCallback === 'function') {
                    window.requestIdleCallback(run, { timeout: 2000 });
                } else {
                    window.setTimeout(run, 0);
                }
            },

            _paintTile: function (tile, blob, done) {
                const url = URL.createObjectURL(blob);
                tile.onload = () => {
                    URL.revokeObjectURL(url);
                    done(null, tile);
                };
                tile.onerror = (e) => {
                    URL.revokeObjectURL(url);
                    done(e, tile);
                };
                tile.src = url;
            }
        });

        return new Hybrid(
            BASE_TILE_URL,
            Object.assign({}, TILE_PERF_OPTIONS, {
                maxZoom: TILE_MAX_ZOOM,
                attribution: BASE_ATTRIBUTION,
                pmtilesUrl: PMTILES_URL,
                layerConfig: BASE_LAYER_CONFIG,
                fallbackOnCorrectionFailure: true
            })
        );
    }

    /**
     * The corrector ships as an esbuild IIFE, so which global object its
     * namespace lands on depends on how Lightning Web Security sandboxes the
     * injected script — check every reachable one.
     */
    resolveCorrector() {
        const candidates = [
            typeof window !== 'undefined' ? window.IndiaBoundaryCorrector : null,
            typeof globalThis !== 'undefined' ? globalThis.IndiaBoundaryCorrector : null
        ];
        return candidates.find((c) => c && typeof c.extendLeaflet === 'function') || null;
    }

    /**
     * Swaps the corrected layer out for the plain one if its tiles fail
     * outright — it paints tiles as blob: object URLs, which a stricter site
     * CSP can block, and a blank basemap is worse than an imperfect border.
     */
    watchCorrectedLayer(layer) {
        let errors = 0;
        let settled = false;

        layer.on('tileload', () => {
            settled = true;
        });

        layer.on('correctionerror', (e) => {
            console.warn('kenAlumniMap: boundary corrections unavailable', e && e.error);
        });

        layer.on('tileerror', () => {
            if (settled) {
                return;
            }
            errors += 1;
            if (errors < CORRECTED_TILE_ERROR_LIMIT) {
                return;
            }
            settled = true;
            console.warn('kenAlumniMap: corrected tiles failed to render, falling back to uncorrected tiles');
            if (this.map && this.map.hasLayer(layer)) {
                this.map.removeLayer(layer);
            }
            this.addPlainBaseLayer();
        });
    }

    addPlainBaseLayer() {
        const L = window.L;
        this.tileLayer = L.tileLayer(
            BASE_TILE_URL,
            Object.assign({}, TILE_PERF_OPTIONS, {
                maxZoom: TILE_MAX_ZOOM,
                attribution: BASE_ATTRIBUTION
            })
        );
        this.tileLayer.addTo(this.map);
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
            const previous = this.currentLevel;
            this.currentLevel = level;
            this.drawBubbles(level, previous);
        }
    }

    /**
     * Asks the basemap to pre-build the next zoom level's corrected tiles for
     * the current viewport while the browser is idle. No-op for the plain
     * fallback layer, which has nothing to pre-build.
     */
    warmNextZoom() {
        if (!this.map || !this.tileLayer || typeof this.tileLayer.warmZoom !== 'function') {
            return;
        }
        this.tileLayer.warmZoom(this.map.getZoom() + 1);
    }

    nodesForLevel(level) {
        if (level === 'country') {
            return this.countryNodes;
        }
        return level === 'state' ? this.stateLevelNodes : this.cityLevelNodes;
    }

    drawBubbles(level, previousLevel) {
        this.bubbleLayer.clearLayers();
        const nodes = this.nodesForLevel(level);
        if (!nodes.length) {
            return;
        }
        const splitting =
            previousLevel && LEVEL_RANK[level] > LEVEL_RANK[previousLevel]
                ? this.nodesForLevel(previousLevel)
                : null;
        const max = nodes.reduce((m, n) => Math.max(m, n.count), 1);
        nodes.forEach((n) => {
            const marker = window.L.marker(n.pos, {
                icon: this.buildIcon(n.count, max, n.isTerminal),
                keyboard: false
            });
            const tip = document.createElement('span');
            tip.textContent = `${n.name} · ${n.count.toLocaleString('en-IN')} alumni`;
            marker.bindTooltip(tip, { direction: 'top', offset: [0, -8], opacity: 0.95 });
            if (n.isTerminal) {
                // Everyone here is in one place — zooming can't split it, so open
                // the people sidebar straight away (yellow pin).
                marker.on('click', () => this.openLocation(n));
            } else {
                // Aggregates multiple places — clicking the number zooms in to split
                // it (dark circle).
                marker.on('click', () => this.map.flyTo(n.pos, n.drillZoom, { duration: 0.8 }));
            }
            this.bubbleLayer.addLayer(marker);
            if (splitting) {
                this.animateSplit(marker, n, splitting);
            }
        });
    }

    /**
     * Makes a newly revealed bubble appear to break out of the aggregate it came
     * from: it starts small and transparent at its parent's screen position and
     * slides to its own. The parent is the nearest node from the level we just
     * left, which is what a viewer reads as "that big number split into these".
     *
     * The offset goes on the inner element via CSS custom properties so it never
     * fights Leaflet's own translate3d on the marker wrapper.
     */
    animateSplit(marker, node, parentNodes) {
        const el = marker.getElement();
        const inner = el && el.firstElementChild;
        if (!inner) {
            return;
        }
        const parent = this.nearestNode(node, parentNodes) || node;
        const here = this.map.latLngToLayerPoint(node.pos);
        const from = this.map.latLngToLayerPoint(parent.pos);
        // A parent sitting on the same centroid as its child (a state whose
        // alumni are all in one city) gives a zero offset — still animate, so
        // the bubble scales and fades in rather than appearing with no
        // transition at all.
        const dx = Math.round(from.x - here.x);
        const dy = Math.round(from.y - here.y);

        el.style.setProperty('--spawn-x', `${dx}px`);
        el.style.setProperty('--spawn-y', `${dy}px`);
        el.classList.add('is-spawning');
        // Force the start state to be committed before releasing the transition,
        // otherwise the browser collapses both frames into no animation at all.
        void inner.offsetWidth;
        requestAnimationFrame(() => {
            el.classList.remove('is-spawning');
            window.setTimeout(() => {
                el.style.removeProperty('--spawn-x');
                el.style.removeProperty('--spawn-y');
            }, SPLIT_ANIMATION_MS);
        });
    }

    nearestNode(node, candidates) {
        let best = null;
        let bestDistance = Infinity;
        candidates.forEach((c) => {
            const dLat = c.pos[0] - node.pos[0];
            const dLng = c.pos[1] - node.pos[1];
            const d = dLat * dLat + dLng * dLng;
            if (d < bestDistance) {
                bestDistance = d;
                best = c;
            }
        });
        return best;
    }

    buildIcon(count, max, isTerminal) {
        const L = window.L;
        if (isTerminal) {
            // Deepest level — the people are in this one place and zooming can't
            // split them further, so it renders as the yellow pin.
            return L.divIcon({
                className: 'ken-map-icon',
                html: `<div class="map-pin"><span class="map-pin-dot"></span>${count}</div>`,
                iconSize: [46, 34],
                iconAnchor: [12, 34]
            });
        }
        // Still drillable — zooming in will break this into smaller groups, so it
        // renders as the dark circle (sized by how many it aggregates).
        const size = Math.min(54, 28 + Math.round(20 * Math.sqrt(count / max)));
        const fontSize = size >= 46 ? 13 : 12;
        return L.divIcon({
            className: 'ken-map-icon',
            html: `<div class="map-bubble" style="width:${size}px;height:${size}px;font-size:${fontSize}px">${count}</div>`,
            iconSize: [size, size],
            iconAnchor: [size / 2, size / 2]
        });
    }

    openLocation(node) {
        this.sidebarOpen = true;
        this.sidebarTitle = node.name || 'This location';
        this.sidebarCount = node.count || 0;
        this.sidebarError = '';
        this.sidebarPeople = [];

        if (this.isGuest) {
            // Guests never load names — the template renders the login/register prompt.
            this.sidebarLoading = false;
            return;
        }

        this.sidebarLoading = true;
        getAlumniAtLocation({ cities: node.cities || [], countries: node.countries || [] })
            .then((people) => {
                this.sidebarPeople = (people || []).map((p) => ({
                    personId: p.personId,
                    constituentRoleId: p.constituentRoleId,
                    name: p.name,
                    subtitle: p.subtitle,
                    profileImage: p.profileImage,
                    hasImage: !!p.profileImage,
                    initials: this.computeInitials(p.name)
                }));
            })
            .catch((e) => {
                this.sidebarError =
                    (e && e.body && e.body.message) || 'We could not load the people for this location.';
            })
            .finally(() => {
                this.sidebarLoading = false;
            });
    }

    closeSidebar() {
        this.sidebarOpen = false;
    }

    handleAvatarError(event) {
        // Broken/expired photo URL — fall back to the initials avatar.
        const personId = event.currentTarget.dataset.personId;
        this.sidebarPeople = this.sidebarPeople.map((p) =>
            p.personId === personId ? { ...p, hasImage: false } : p
        );
    }

    handleProfileClick(event) {
        const el = event.currentTarget;
        const personId = el.dataset.personId || '';
        const constituentRoleId = el.dataset.roleId || '';
        const name = el.dataset.name || '';
        this.dispatchEvent(
            new CustomEvent('profileselect', {
                detail: { personId, constituentRoleId, name },
                bubbles: true,
                composed: true
            })
        );
    }

    handleGuestLogin() {
        this.dispatchEvent(
            new CustomEvent('guestaction', {
                detail: { action: 'login' },
                bubbles: true,
                composed: true
            })
        );
    }

    stopPropagation(event) {
        event.stopPropagation();
    }
}