import { LightningElement, api } from 'lwc';

const TABS = [
    { id: 'upcoming', label: 'All Events' },
    { id: 'myevents', label: 'My Events' },
    { id: 'past',     label: 'Past Events' },
    { id: 'hosted',   label: 'Hosted' }
];

export default class KenEventsTabsV2 extends LightningElement {
    @api activeTab = 'upcoming';

    get tabs() {
        return TABS.map(t => ({
            ...t,
            tabClass: t.id === this.activeTab ? 'tab tab--active' : 'tab'
        }));
    }

    handleTab(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('tabchange', { detail: { id } }));
    }
}