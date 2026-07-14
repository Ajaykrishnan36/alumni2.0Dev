import { LightningElement, api } from 'lwc';

export default class KenMentorshipTasksPanelV2 extends LightningElement {
    @api tasks = [];

    get decorated() {
        return (this.tasks || []).map(t => ({
            ...t,
            // Defensive defaults — title/desc may arrive null from Apex.
            title: t.title || 'Untitled task',
            desc: t.desc || '',
            pillLabel: t.status === 'done' ? 'On Hold' : 'In Progress',
            pillClass: t.status === 'done' ? 'pill pill--done' : 'pill pill--progress',
            priorityClass: t.priority === 'High' ? 'priority priority--high' : 'priority'
        }));
    }
    get hasTasks() { return (this.tasks || []).length > 0; }

    handleAdd() {
        this.dispatchEvent(new CustomEvent('addtask'));
    }
    handleTask(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('taskclick', { detail: { id } }));
    }
}