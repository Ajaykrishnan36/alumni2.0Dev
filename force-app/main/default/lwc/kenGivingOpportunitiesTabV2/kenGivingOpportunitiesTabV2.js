import { LightningElement, track, wire } from 'lwc';
import getOpportunities from '@salesforce/apex/KenGivingDashboardController.getOpportunities';

const IMG_FALLBACK = 'linear-gradient(135deg, #eef2ff 0%, #c7d2fe 60%, #a5b4fc 100%)';
function imgStyleFor(url) {
    if (url && /^https?:\/\//i.test(url)) {
        return `background-image:url('${String(url).replace(/'/g, "\\'")}');background-size:cover;background-position:center;`;
    }
    return `background:${IMG_FALLBACK};`;
}
function hasImg(url) { return !!(url && /^https?:\/\//i.test(url)); }

const FILTERS = [
    { key: 'all', label: 'All' },
    { key: 'Scholarships', label: 'Scholarships' },
    { key: 'Infrastructure', label: 'Infrastructure' },
    { key: 'Campus Development', label: 'Campus Development' },
    { key: 'Batch Fund', label: 'Batch Fund' },
    { key: 'Student Support', label: 'Student Support' }
];

export default class KenGivingOpportunitiesTabV2 extends LightningElement {
    @track rows = [];
    @track activeFilter = 'all';
    @track searchTerm = ''; // QA Bug #129 — free-text search
    loading = true;

    @wire(getOpportunities)
    wired({ data }) {
        if (data) { this.rows = data; this.loading = false; }
    }

    get filters() {
        return FILTERS.map(f => ({
            ...f,
            cls: 'opp-pill' + (f.key === this.activeFilter ? ' opp-pill--on' : '')
        }));
    }

    get featured() {
        const list = this._filtered();
        return list.find(r => r.isFeatured) || list[0] || null;
    }
    get hasFeatured() { return !!this.featured; }
    get featuredDecorated() {
        const f = this.featured; if (!f) return null;
        return {
            ...f,
            progressStyle: 'width:' + (f.progressPercent || 0) + '%;',
            imgStyle: imgStyleFor(f.imageUrl),
            hasImage: hasImg(f.imageUrl)
        };
    }

    get gridCards() {
        const list = this._filtered();
        const featuredId = this.featured && this.featured.id;
        return list
            .filter(r => r.id !== featuredId)
            .map(r => ({
                ...r,
                progressStyle: 'width:' + (r.progressPercent || 0) + '%;',
                pctLabel: (r.progressPercent || 0) + '% funded',
                daysLabel: (r.daysLeft || 0) + ' days left',
                contributorsLabel: (r.contributorsCount || 0) + ' contributors',
                imgStyle: imgStyleFor(r.imageUrl),
                hasImage: hasImg(r.imageUrl),
                cardKey: r.id || ('o-' + Math.random())
            }));
    }

    get hasGrid() { return this.gridCards.length > 0; }
    get hasAny() { return this._filtered().length > 0; }
    get headerCountLine() {
        const total = this.rows.length;
        return `${total} active campaign${total === 1 ? '' : 's'} live this season`;
    }

    _filtered() {
        let list = this.activeFilter === 'all'
            ? this.rows.slice()
            : this.rows.filter(r => (r.category || '').toLowerCase() === this.activeFilter.toLowerCase());
        // QA Bug #129 — apply free-text search across title / category / cause / story.
        const term = (this.searchTerm || '').trim().toLowerCase();
        if (term) {
            list = list.filter(r => {
                const hay = [r.title, r.category, r.cause, r.department, r.story, r.description]
                    .map(x => (x == null ? '' : String(x)).toLowerCase()).join(' ');
                return hay.indexOf(term) > -1;
            });
        }
        return list;
    }

    handleFilter(e) { this.activeFilter = e.currentTarget.dataset.key; }
    handleSearch(e) { this.searchTerm = (e && e.target && e.target.value) || ''; }
    handleGiveFeatured() {
        const f = this.featured;
        if (!f) return;
        this.dispatchEvent(new CustomEvent('donate', { detail: { id: f.id } }));
    }
    handleGiveCard(e) {
        this.dispatchEvent(new CustomEvent('donate', { detail: { id: e.currentTarget.dataset.id } }));
    }
    handleDetails(e) {
        this.dispatchEvent(new CustomEvent('details', { detail: { id: e.currentTarget.dataset.id } }));
    }
}