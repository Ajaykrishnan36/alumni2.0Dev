import { LightningElement, api } from 'lwc';

const TABS = [
    { id: 'all',         label: 'All Alumni' },
    { id: 'connections', label: 'Your Connections' }
];

export default class KenNetworkTopTabsV2 extends LightningElement {
    @api activeTab = 'all';

    get tabs() {
        return TABS.map(t => ({
            ...t,
            cssClass: t.id === this.activeTab ? 'tab tab--active' : 'tab'
        }));
    }

    handleClick(event) {
        this.dispatchEvent(new CustomEvent('tabchange', { detail: { id: event.currentTarget.dataset.id } }));
    }
}