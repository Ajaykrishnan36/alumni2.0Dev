import { LightningElement, api } from 'lwc';

const TABS = [
    { id: 'all', label: 'All Updates' },
    { id: 'joined', label: 'From Joined' },
    { id: 'created', label: 'From Created' },
    { id: 'discover', label: 'Discover' }
];

export default class KenGroupsTopTabsV2 extends LightningElement {
    @api activeTab = 'all';

    get tabs() {
        return TABS.map(t => ({
            ...t,
            cssClass: t.id === this.activeTab ? 'feed-tab feed-tab--active' : 'feed-tab'
        }));
    }

    handleClick(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('tabchange', { detail: { id } }));
    }
}