import { LightningElement, api } from 'lwc';

const TABS = [
    { id: 'connections', label: 'Connections' },
    { id: 'mentees', label: 'Your Mentees' },
    { id: 'tasks', label: 'Tasks' },
    { id: 'sessions', label: 'Sessions' }
];

export default class KenMentorshipTopTabsV2 extends LightningElement {
    @api activeTab = 'connections';

    get tabs() {
        return TABS.map(t => ({
            ...t,
            cssClass: t.id === this.activeTab ? 'tab tab--active' : 'tab'
        }));
    }

    handleClick(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('tabchange', { detail: { id } }));
    }
}