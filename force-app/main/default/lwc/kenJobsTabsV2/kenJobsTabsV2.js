import { LightningElement, api } from 'lwc';

export default class KenJobsTabsV2 extends LightningElement {
    @api activeTab = 'recommended';
    @api recommendedCount = 0;
    @api allCount = 0;

    get tabs() {
        const list = [
            { id: 'recommended', label: `Recommended Jobs (${this.recommendedCount})` },
            { id: 'all',         label: `All Jobs (${this.allCount})` }
        ];
        return list.map(t => ({ ...t, cls: t.id === this.activeTab ? 'tab tab--active' : 'tab' }));
    }

    handleTab(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('tabchange', { detail: { id } }));
    }
}