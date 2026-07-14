import { LightningElement, track } from 'lwc';

const STAGES = [
    { id: 1, label: 'Registered',  n: 1, date: '10 Aug, 2025',  state: 'done' },
    { id: 2, label: 'Eligible',    n: 2, date: '24 Aug, 2025',  state: 'done' },
    { id: 3, label: 'Applied',     n: 3, date: '05 Sept, 2025', state: 'done' },
    { id: 4, label: 'Shortlisted', n: 4, date: '18 Sept, 2025', state: 'done' },
    { id: 5, label: 'Interview',   n: 5, date: '03 Oct, 2025',  state: 'current' },
    { id: 6, label: 'Offer',       n: 6, date: '—',             state: '' }
];
const STATS = [
    { id: 1, k: 'Applications', v: '6', sub: '+2 this week' },
    { id: 2, k: 'Interviews',   v: '3', sub: '1 upcoming' },
    { id: 3, k: 'Offers',       v: '1', sub: '1 pending review' },
    { id: 4, k: 'Exams',        v: '2', sub: 'Scheduled' }
];
const UPCOMING = [
    { id: 1, co: 'Goldman Sachs', l: 'G', col: '#5F6271', date: '12 Nov, 2025', role: 'Quant Analyst',     status: 'Upcoming', isClosed: false },
    { id: 2, co: 'Microsoft',     l: 'M', col: '#0078D4', date: '18 Nov, 2025', role: 'SDE Intern',         status: 'Open',     isClosed: false },
    { id: 3, co: 'Adobe',         l: 'A', col: '#FF0000', date: '24 Nov, 2025', role: 'Product Designer',   status: 'Open',     isClosed: false },
    { id: 4, co: 'Salesforce',    l: 'S', col: '#00A1E0', date: '30 Oct, 2025', role: 'Cloud Engineer',     status: 'Closed',   isClosed: true }
];

export default class KenJobPlacementCycleV2 extends LightningElement {
    @track activeCycle = 'cycle1';

    get stages() {
        return STAGES.map(s => ({
            ...s,
            cls: 'stage stage--' + (s.state || 'pending'),
            num: s.state === 'done' ? '✓' : s.n
        }));
    }
    get stats() { return STATS; }
    get upcoming() {
        return UPCOMING.map(r => ({
            ...r,
            logoStyle: 'background:' + r.col,
            pillCls: 'pill pill--' + r.status.toLowerCase(),
            btnCls: r.isClosed ? 'btn btn--outline' : 'btn btn--primary',
            action: r.isClosed ? 'View' : 'Apply'
        }));
    }

    handleCycleChange(event) { this.activeCycle = event.target.value; }
    handleBack() { this.dispatchEvent(new CustomEvent('back')); }
    handleRowAction(event) {
        const id = parseInt(event.currentTarget.dataset.id, 10);
        this.dispatchEvent(new CustomEvent('rowaction', { detail: { id } }));
    }
}