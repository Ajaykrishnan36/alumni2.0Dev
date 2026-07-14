import { LightningElement, api } from 'lwc';

const TABS = [
    { id: 'Approved', label: 'Approved' },
    { id: 'In Review', label: 'In Review' },
    { id: 'Rejected', label: 'Rejected' }
];

export default class KenSurveysTabsV2 extends LightningElement {
    @api activeTab = 'Approved';

    get tabs() {
        return TABS.map(t => ({ ...t, cls: this.activeTab === t.id ? 'tab tab--active' : 'tab' }));
    }
    handleTab(event) {
        this.dispatchEvent(new CustomEvent('tabchange', { detail: { id: event.currentTarget.dataset.id } }));
    }
}