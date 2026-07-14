import { LightningElement, api } from 'lwc';

const TABS = [
    { key: 'dashboard',        ico: '▦',  label: 'Dashboard' },
    { key: 'opportunities',    ico: '♡',  label: 'Opportunities' },
    { key: 'my-giving',        ico: '🏆', label: 'My Giving' },
    { key: 'start-initiative', ico: '✦',  label: 'Start Initiative' },
    { key: 'impact-updates',   ico: '📈', label: 'Impact Updates' }
];

export default class KenGivingSubNavV2 extends LightningElement {
    @api activeTab = 'opportunities';

    get tabs() {
        return TABS.map(t => ({ ...t, cssClass: t.key === this.activeTab ? 'g-tab g-tab--active' : 'g-tab' }));
    }

    handleTab(event) {
        this.dispatchEvent(new CustomEvent('tabchange', { detail: { key: event.currentTarget.dataset.key } }));
    }
    handleNew() {
        this.dispatchEvent(new CustomEvent('newinitiative'));
    }
}