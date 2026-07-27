import { LightningElement, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import LEAFLET_JS from '@salesforce/resourceUrl/kenLeafletJs';
import GEO_DATA from '@salesforce/resourceUrl/kenGeoData';
import getAlumniLocationCounts from '@salesforce/apex/KenAlumniMapController.getAlumniLocationCounts';
import getAlumniAtLocation from '@salesforce/apex/KenAlumniMapController.getAlumniAtLocation';

const COUNTRY_MAX_ZOOM = 3;
const STATE_MAX_ZOOM = 5;
const STATE_VIEW_ZOOM = 5;
const CITY_VIEW_ZOOM = 7;

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
                getAlumniLocationCounts()
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
            maxZoom: 9,
            zoomSnap: 0.5,
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
        this.map.on('zoomend', () => this.syncLevel());

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

    setupBaseLayer() {
        const L = window.L;
        // Standard OpenStreetMap tiles (leafletjs.com's own demo style), per
        // explicit request despite the known Kashmir/disputed-border
        // rendering issue (shared by every free tile provider, since they
        // all render from the same OSM boundary dataset — not fixed by this
        // style choice). Tracked separately; would need a dedicated
        // India-compliant provider (e.g. Bhuvan, MapmyIndia) to resolve.
        // maxZoom stays capped at 9 (not OSM's native 19) — this map is an
        // aggregate country/state/city clustering view, not street-level.
        this.tileLayer = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            maxZoom: 9,
            attribution:
                '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> contributors'
        });
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
            this.currentLevel = level;
            this.drawBubbles(level);
        }
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
        });
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