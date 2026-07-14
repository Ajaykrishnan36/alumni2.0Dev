// Tasks rail for the dashboard right column. Decorates TaskRow rows with status/priority classes,
// renders an illustrated empty state with a full-width CTA when there are no tasks.
import { LightningElement, api } from 'lwc';

const PRIORITY_PALETTE = ['#A78BFA', '#60A5FA', '#F472B6', '#FBBF24', '#34D399'];

function initialOf(name) {
    if (!name || typeof name !== 'string') return '?';
    return name.trim().charAt(0).toUpperCase() || '?';
}
function statusClass(status) {
    const s = (status || '').toLowerCase();
    if (s.indexOf('progress') >= 0) return 'status-pill status-pill--inprogress';
    if (s.indexOf('hold') >= 0) return 'status-pill status-pill--onhold';
    if (s.indexOf('complet') >= 0 || s === 'done') return 'status-pill status-pill--completed';
    if (s.indexOf('pend') >= 0) return 'status-pill status-pill--pending';
    return 'status-pill status-pill--pending';
}
function statusLabel(status) {
    const s = (status || '').toLowerCase();
    if (s.indexOf('progress') >= 0) return 'In Progress';
    if (s.indexOf('hold') >= 0) return 'On-Hold';
    if (s.indexOf('complet') >= 0 || s === 'done') return 'Completed';
    if (s.indexOf('pend') >= 0) return 'Pending';
    return status || 'Pending';
}
function priorityClass(p) {
    const v = (p || '').toLowerCase();
    if (v === 'high') return 'priority priority--high';
    if (v === 'medium') return 'priority priority--medium';
    if (v === 'low') return 'priority priority--low';
    return 'priority priority--medium';
}
function safeImg(url) {
    if (!url || typeof url !== 'string') return null;
    if (/^https?:\/\//i.test(url) || url.charAt(0) === '/') return url;
    return null;
}
function dueDateLabel(endDate) {
    if (!endDate) return 'No due date';
    const d = new Date(endDate);
    if (isNaN(d.getTime())) return endDate;
    return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
}

export default class KenMentorshipTasksV2 extends LightningElement {
    @api tasks = [];

    get decorated() {
        return (this.tasks || []).map((t, i) => {
            const img = safeImg(t && t.assigneeAvatar);
            const color = PRIORITY_PALETTE[i % PRIORITY_PALETTE.length];
            return {
                key: (t && t.id) || `task-${i}`,
                id: (t && t.id) || null,
                title: (t && t.title) || 'Untitled task',
                description: (t && t.description) || '',
                status: statusLabel(t && t.status),
                statusClass: statusClass(t && t.status),
                priority: (t && t.priority) || 'Medium',
                priorityClass: priorityClass(t && t.priority),
                assigneeName: (t && t.assigneeName) || 'Unassigned',
                assigneeInitial: initialOf((t && t.assigneeName) || ''),
                avatarStyle: img
                    ? `background-image:url('${img.replace(/'/g, "\\'")}');background-size:cover;background-position:center;`
                    : `background:${color};color:#fff;`,
                showInitial: !img,
                dueDateLabel: dueDateLabel(t && t.endDate)
            };
        });
    }

    get hasTasks() { return (this.tasks || []).length > 0; }

    handleAddTask() {
        this.dispatchEvent(new CustomEvent('addtask'));
    }
    handleTaskClick(event) {
        const id = event.currentTarget.dataset.id;
        this.dispatchEvent(new CustomEvent('taskclick', { detail: { id } }));
    }
}