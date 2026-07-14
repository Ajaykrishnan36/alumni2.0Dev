// Mentorship Connections rail — horizontal scrollable card carousel.
// Pure presentational: consumes MentorshipConnectionRow[] from the parent dashboard.
// All search/sort/filter is local; dispatches `search` so the parent can swap dataset
// if it ever wants server-side search.
import { LightningElement, api, track } from 'lwc';

const PALETTE = ['#E6BFA1', '#F4C2C2', '#C8B6FF', '#FFD6A5', '#E8B4D6', '#67A1C8'];

function initialOf(name) {
    if (!name || typeof name !== 'string') return '?';
    const trimmed = name.trim();
    return trimmed.charAt(0).toUpperCase() || '?';
}
function safeImg(url) {
    if (!url || typeof url !== 'string') return null;
    if (/^https?:\/\//i.test(url) || url.charAt(0) === '/') return url;
    return null;
}

export default class KenMentorshipConnectionsV2 extends LightningElement {
    @api connections = [];

    @track searchTerm = '';
    @track sortBy = 'name';
    @track showFilters = false;
    @track roleFilter = 'all'; // 'all' | 'mentor' | 'mentee'

    get count() { return (this.decorated || []).length; }
    get hasConnections() { return this.count > 0; }
    get hasResults() { return this.filtered.length > 0; }
    get emptyForSearch() { return this.hasConnections && !this.hasResults; }

    get decorated() {
        return (this.connections || []).map((r, i) => {
            const isMentor = r && r.currentUserIsMentor === false; // counterpart is mentor
            const img = safeImg(r && r.profileImage);
            const name = (r && r.name) || '';
            const role = (r && r.title) || (r && r.jobFunction) || '';
            const company = (r && r.company) || '';
            const city = (r && r.location) || (r && r.currentCity) || '';
            const color = PALETTE[i % PALETTE.length];
            const initial = initialOf(name);
            const roleCompany = role && company
                ? `${role} · ${company}`
                : (role || company || '');
            return {
                key: (r && (r.personAccountId || r.id)) || `c-${i}`,
                id: (r && r.personAccountId) || (r && r.id) || null,
                name,
                roleCompany,
                city,
                initial,
                avatarStyle: img
                    ? `background-image:url('${img.replace(/'/g, "\\'")}');background-size:cover;background-position:center;`
                    : `background:${color};color:#fff;`,
                showInitial: !img,
                isMentor
            };
        });
    }

    get filterAllCls() { return 'rf-pill' + (this.roleFilter === 'all' ? ' rf-pill--on' : ''); }
    get filterMentorCls() { return 'rf-pill' + (this.roleFilter === 'mentor' ? ' rf-pill--on' : ''); }
    get filterMenteeCls() { return 'rf-pill' + (this.roleFilter === 'mentee' ? ' rf-pill--on' : ''); }
    get filtersButtonCls() {
        return 'mc-filters' + (this.showFilters ? ' mc-filters--on' : '')
            + (this.roleFilter !== 'all' ? ' mc-filters--active' : '');
    }

    get filtered() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        let list = this.decorated;
        if (this.roleFilter === 'mentor')      list = list.filter(c => c.isMentor === true);
        else if (this.roleFilter === 'mentee') list = list.filter(c => c.isMentor === false);
        if (term) {
            list = list.filter(c =>
                (c.name && c.name.toLowerCase().indexOf(term) >= 0) ||
                (c.roleCompany && c.roleCompany.toLowerCase().indexOf(term) >= 0) ||
                (c.city && c.city.toLowerCase().indexOf(term) >= 0)
            );
        }
        if (this.sortBy === 'name') {
            list = [...list].sort((a, b) => (a.name || '').localeCompare(b.name || ''));
        } else if (this.sortBy === 'role') {
            list = [...list].sort((a, b) => (a.roleCompany || '').localeCompare(b.roleCompany || ''));
        }
        return list;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
        this.dispatchEvent(new CustomEvent('search', { detail: { term: this.searchTerm } }));
    }
    handleSort(event) {
        this.sortBy = event.target.value || 'name';
    }
    handleCard(event) {
        const id = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this.dispatchEvent(new CustomEvent('cardclick', { detail: { id, name } }));
    }
    handleFilters() {
        // Toggle the inline role-filter panel (mentor / mentee / all).
        this.showFilters = !this.showFilters;
        // Keep the legacy event for any parent that wants to listen.
        this.dispatchEvent(new CustomEvent('openfilters', { detail: { open: this.showFilters } }));
    }
    handleRoleFilter(event) {
        this.roleFilter = event.currentTarget.dataset.role || 'all';
    }
    handleClearRoleFilter() {
        this.roleFilter = 'all';
    }
}