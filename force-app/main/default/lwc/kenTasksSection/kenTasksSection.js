import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

export default class KenTasksSection extends NavigationMixin(LightningElement) {
    @api tasks = [];
    @api mentorOptions = [];
    @api menteeOptions = [];
    @api isLoading = false;
    @api isBeAMentorOn = false;
    showAddTaskModal = false;
    openTaskMenuId = null;
    modalMode = 'add';
    editingTask = null;
    _docClickHandler;
    expandedDescriptionTaskIds = new Set();

    normalizeText(value) {
        if (value === null || value === undefined) return '';
        return String(value);
    }

    getDescriptionPreview(fullText, maxChars) {
        const text = this.normalizeText(fullText).trim();
        if (!text) return { text: '', isTruncated: false };
        if (!maxChars || maxChars <= 0) return { text, isTruncated: false };
        if (text.length <= maxChars) return { text, isTruncated: false };
        return { text: text.slice(0, maxChars) + 'â€¦', isTruncated: true };
    }

    get displayTasks() {
        if (!this.tasks || this.tasks.length === 0) {
            return [];
        }
        return this.tasks.map(task => ({
            ...task,
            statusClass: this.getStatusClass(task.status),
            priorityClass: this.getPriorityClass(task.priority),
            endDateLabel: this.formatDateLabel(task.endDate),
            assigneeName: task.assigneeName || task.assignee || '',
            assigneeAvatar: task.assigneeAvatar || task.assigneeImage || '',
            showAssignee: !!(task.assigneeName || task.assignee),
            isMenuOpen: this.openTaskMenuId === String(task.id),
            isDescriptionExpanded: this.expandedDescriptionTaskIds.has(String(task.id)),
            descriptionFull: this.normalizeText(task.description),
            descriptionPreview: this.getDescriptionPreview(task.description, 70).text,
            isDescriptionTruncated: this.getDescriptionPreview(task.description, 70).isTruncated,
            descriptionToShow: this.expandedDescriptionTaskIds.has(String(task.id))
                ? this.normalizeText(task.description)
                : this.getDescriptionPreview(task.description, 70).text,
            descriptionToggleLabel: this.expandedDescriptionTaskIds.has(String(task.id)) ? 'Show less' : 'Show more'
        }));
    }

    getStatusClass(status) {
        const statusMap = {
            'Active': 'status-badge in-progress',
            'In Progress': 'status-badge in-progress',
            'On-Hold': 'status-badge on-hold',
            'Completed': 'status-badge completed',
            'Pending': 'status-badge pending'
        };
        return statusMap[status] || 'status-badge';
    }

    getPriorityClass(priority) {
        const priorityMap = {
            'High': 'priority-high',
            'Medium': 'priority-medium',
            'Low': 'priority-low'
        };
        return priorityMap[priority] || '';
    }

    formatDateLabel(value) {
        if (!value) {
            return '';
        }

        if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
            const [yyyy, mm, dd] = value.split('-');
            return `${dd}-${mm}-${yyyy}`;
        }
        return value;
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            console.log('Error getting primary color');
        });

        this._docClickHandler = (event) => {
            if (!this.openTaskMenuId) {
                return;
            }
            const clickedInsideMenu = event.composedPath().some((el) => {
                return el?.dataset?.taskMenuRoot === 'true';
            });
            if (!clickedInsideMenu) {
                this.openTaskMenuId = null;
            }
        };
        document.addEventListener('click', this._docClickHandler);
    }

    disconnectedCallback() {
        if (this._docClickHandler) {
            document.removeEventListener('click', this._docClickHandler);
            this._docClickHandler = null;
        }
    }

    handleAddTask() {
        if (this.isLoading) {
            return;
        }
        this.modalMode = 'add';
        this.editingTask = null;
        this.showAddTaskModal = true;
    }

    handleCloseAddTaskModal() {
        this.showAddTaskModal = false;
        this.modalMode = 'add';
        this.editingTask = null;
    }

    handleSaveTask(event) {
        const taskData = event.detail;
        if (this.modalMode === 'edit') {
            this.dispatchEvent(new CustomEvent('edittask', {
                detail: taskData,
                bubbles: true,
                composed: true
            }));
        } else {
            this.dispatchEvent(new CustomEvent('addtask', {
                detail: taskData,
                bubbles: true,
                composed: true
            }));
        }
        this.handleCloseAddTaskModal();
    }

    handleTaskMenu(event) {
        if (this.isLoading) {
            return;
        }
        event.stopPropagation();
        const taskId = event.currentTarget.dataset.taskId;
        this.openTaskMenuId = this.openTaskMenuId === taskId ? null : taskId;
    }

    handleTaskAction(event) {
        if (this.isLoading) {
            return;
        }
        event.stopPropagation();
        const action = event.currentTarget.dataset.action;
        const taskId = event.currentTarget.dataset.taskId;
        this.openTaskMenuId = null;

        if (action === 'edit') {
            const task = (this.tasks || []).find((item) => String(item.id) === String(taskId));
            if (task) {
                this.modalMode = 'edit';
                this.editingTask = { ...task };
                this.showAddTaskModal = true;
            }
            return;
        }

        this.dispatchEvent(new CustomEvent('taskaction', {
            detail: { action, taskId },
            bubbles: true,
            composed: true
        }));
    }

    handleToggleDescription(event) {
        event.stopPropagation();
        const taskId = event.currentTarget?.dataset?.taskId;
        if (!taskId) return;
        const id = String(taskId);
        const next = new Set(this.expandedDescriptionTaskIds);
        if (next.has(id)) {
            next.delete(id);
        } else {
            next.add(id);
        }
        this.expandedDescriptionTaskIds = next;
    }

    handleBecomeMentor() {
        try {
            sessionStorage.setItem('ken_setting_active_tab', 'Mentorship');
        } catch {
            // ignore storage errors
        }
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'settings__c' }
        });
    }
}