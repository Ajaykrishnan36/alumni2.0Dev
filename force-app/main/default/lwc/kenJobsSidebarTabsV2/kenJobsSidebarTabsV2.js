import { LightningElement, api } from 'lwc';

export default class KenJobsSidebarTabsV2 extends LightningElement {
    @api activeTab = 'applied';

    get tabs() {
        const list = [
            { id: 'applied', label: 'Applied Jobs' },
            { id: 'saved',   label: 'Saved Jobs' }
        ];
        return list.map(t => ({ ...t, cls: t.id === this.activeTab ? 'side-tab side-tab--active' : 'side-tab' }));
    }

    handleTab(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('tabchange', { detail: { id } }));
    }
}