/*
 * Fundraise (V2)
 *
 * Reads from Ken_Giving_Opportunity__c via KenGivingV2Controller.getFundraiseOpportunities().
 * Falls back to mock data if the call fails.
 */
import { LightningElement, track } from 'lwc';
import getFundraiseOpportunities from '@salesforce/apex/KenGivingV2Controller.getFundraiseOpportunities';

const TABS = [
    { id:'active', label:'Active' },
    { id:'past',   label:'Completed' },
    { id:'mine',   label:'My Contributions' }
];
const MOCK_CAMPAIGNS = [
    { id:1, title:'New Library Wing',           desc:'Help us build a 24/7 study space with collaborative zones, quiet pods & digital tools.', raised:4220000, goal:6000000, donors:312, days:24, color:'#3061FF', cause:'Infrastructure', status:'Live' },
    { id:2, title:'Scholarships for 2026',      desc:'Fund 50 merit-cum-means scholarships for incoming students.',                              raised:1850000, goal:2500000, donors:148, days:42, color:'#19A974', cause:'Education',      status:'Live' },
    { id:3, title:'Sports Equipment Drive',     desc:'New gym equipment, sports kits, and a covered basketball court.',                          raised:780000,  goal:1500000, donors:89,  days:18, color:'#F59E0B', cause:'Sports',         status:'Live' }
];

function inr(n) {
    if (n == null) return '';
    if (n >= 10000000) return `₹${(n/10000000).toFixed(1)}Cr`;
    if (n >= 100000)   return `₹${(n/100000).toFixed(1)}L`;
    if (n >= 1000)     return `₹${(n/1000).toFixed(0)}k`;
    return `₹${n}`;
}

function mapDto(dto) {
    return {
        id: dto.id,
        title: dto.title,
        desc: dto.shortDesc,
        raised: dto.raised || 0,
        goal: dto.target || 0,
        donors: dto.contributors || 0,
        days: dto.daysLeft || 0,
        color: dto.color || '#3061FF',
        cause: dto.cause || '',
        status: dto.status
    };
}

export default class KenFundraiseViewPageV2 extends LightningElement {
    @track activeTab = 'active';
    @track toastMessage = '';
    @track toastVisible = false;
    @track campaignsData = [];
    @track isLoading = true;
    _toastTimer = null;

    connectedCallback() {
        this._load();
    }

    async _load() {
        this.isLoading = true;
        try {
            const data = await getFundraiseOpportunities();
            if (data && data.length) {
                this.campaignsData = data.map(mapDto);
            } else {
                this.campaignsData = MOCK_CAMPAIGNS;
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Fundraise load error', e);
            this.campaignsData = MOCK_CAMPAIGNS;
        }
        this.isLoading = false;
    }

    get tabs() { return TABS.map(t => ({ ...t, tabClass: t.id === this.activeTab ? 'tab tab--active' : 'tab' })); }

    get filteredCampaigns() {
        if (this.activeTab === 'past') {
            return this.campaignsData.filter(c => c.status === 'Closed');
        }
        if (this.activeTab === 'mine') {
            return [];
        }
        // active default: Live or anything not Closed
        return this.campaignsData.filter(c => c.status !== 'Closed');
    }

    get campaigns() {
        return this.filteredCampaigns.map(c => {
            const pct = c.goal ? Math.min(100, Math.round((c.raised / c.goal) * 100)) : 0;
            return {
                ...c,
                coverStyle: `background:linear-gradient(135deg, ${c.color}, ${c.color}99);`,
                progressStyle: `width:${pct}%; background:${c.color};`,
                pctLabel: `${pct}% funded`,
                raisedLabel: inr(c.raised),
                goalLabel: `of ${inr(c.goal)}`
            };
        });
    }

    handleTab(event) { this.activeTab = event.currentTarget.dataset.id; }
    handleContribute() { this._showToast('Please visit Giving to contribute'); }

    _showToast(msg) {
        this.toastMessage = msg;
        this.toastVisible = true;
        if (this._toastTimer) clearTimeout(this._toastTimer);
        this._toastTimer = setTimeout(() => { this.toastVisible = false; }, 2400);
    }
    disconnectedCallback() { if (this._toastTimer) clearTimeout(this._toastTimer); }
}