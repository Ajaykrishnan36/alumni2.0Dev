import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

const TITLE_MAX_LENGTH = 255;

export default class KenAddTaskModal extends LightningElement {
    @api mode = 'add';
    @api taskData;
    @api mentorOptions = [];
    @api menteeOptions = [];

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            console.log('Error getting primary color');
        });
    }
    @track title = '';
    @track endDate = '';
    @track status = '';
    @track priority = '';
    @track assignTo = '';
    @track selectedMentor = '';
    @track descriptionHtml = '';
    @track isBoldActive = false;
    @track isItalicActive = false;
    @track isUnorderedListActive = false;
    @track isOrderedListActive = false;
    @track errors = { title: '', status: '', endDate: '', assignTo: '', assignee: '' };

    titleMaxLength = TITLE_MAX_LENGTH;

    statusOptions = [
        { label: 'Active', value: 'Active' },
        { label: 'In Progress', value: 'In Progress' },
        { label: 'On-Hold', value: 'On-Hold' },
        { label: 'Completed', value: 'Completed' },
        { label: 'Pending', value: 'Pending' }
    ];

    priorityOptions = [
        { label: 'High', value: 'High' },
        { label: 'Medium', value: 'Medium' },
        { label: 'Low', value: 'Low' }
    ];

    richTextEditor = null;
    initialized = false;

    get modalTitle() {
        return this.mode === 'edit' ? 'Edit Task' : 'Add Task';
    }

    get assignToOptions() {
        return [
            { label: 'Mentor', value: 'mentor' },
            { label: 'Mentee', value: 'mentee' }
        ];
    }

    get isAssignToMentor() {
        return this.assignTo === 'mentor';
    }

    get isAssignToMentee() {
        return this.assignTo === 'mentee';
    }

    get assigneeLabel() {
        return this.isAssignToMentee ? 'Choose Mentee' : 'Choose Mentor';
    }

    get assigneePlaceholder() {
        return this.isAssignToMentee ? 'Choose Mentee' : 'Choose Mentor';
    }

    get assigneeOptions() {
        if (this.isAssignToMentee) {
            return this.menteeOptions || [];
        }
        return this.mentorOptions || [];
    }

    get showAssigneeSelector() {
        return this.isAssignToMentor || this.isAssignToMentee;
    }

    get hasAssigneeOptions() {
        return Array.isArray(this.assigneeOptions) && this.assigneeOptions.length > 0;
    }

    get isAssigneeDisabled() {
        return this.showAssigneeSelector && !this.hasAssigneeOptions;
    }

    get noAssigneeMessage() {
        if (!this.showAssigneeSelector || this.hasAssigneeOptions) {
            return '';
        }
        return this.isAssignToMentor ? 'No mentors available.' : 'No mentees available.';
    }

    get minEndDate() {
        const now = new Date();
        return new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString().slice(0, 10);
    }

    get titleErrorClass() {
        return `custom-input${this.errors.title ? ' error' : ''}`;
    }

    get statusErrorClass() {
        return `custom-select${this.errors.status ? ' error' : ''}`;
    }

    get endDateErrorClass() {
        return `custom-input${this.errors.endDate ? ' error' : ''}`;
    }

    get assigneeErrorClass() {
        return `custom-select${this.errors.assignee ? ' error' : ''}`;
    }

    get boldButtonClass() {
        return `toolbar-button ${this.isBoldActive ? 'active' : ''}`;
    }

    get italicButtonClass() {
        return `toolbar-button ${this.isItalicActive ? 'active' : ''}`;
    }

    get unorderedListButtonClass() {
        return `toolbar-button ${this.isUnorderedListActive ? 'active' : ''}`;
    }

    get orderedListButtonClass() {
        return `toolbar-button ${this.isOrderedListActive ? 'active' : ''}`;
    }

    renderedCallback() {
        const editor = this.template.querySelector('.rich-text-area');
        if (editor) {
            if (editor !== this.richTextEditor) {
                this.richTextEditor = editor;
                if (this.descriptionHtml && editor.innerHTML !== this.descriptionHtml) {
                    editor.innerHTML = this.descriptionHtml;
                }
                editor.addEventListener('keyup', () => this.updateButtonStates());
                editor.addEventListener('mouseup', () => this.updateButtonStates());
            } else if (this.descriptionHtml && editor.innerHTML !== this.descriptionHtml) {
                editor.innerHTML = this.descriptionHtml;
            } else if (!this.descriptionHtml && editor.innerHTML) {
                editor.innerHTML = '';
            }
            this.ensureListFormatting();
        }

        if (!this.initialized) {
            this.initializeForm();
            this.initialized = true;
        }
    }

    initializeForm() {
        if (this.mode !== 'edit' || !this.taskData) {
            return;
        }

        this.title = this.taskData.title || '';
        this.endDate = this.normalizeDate(this.taskData.endDate);
        this.status = this.taskData.status || '';
        this.priority = this.taskData.priority || '';
        this.assignTo = this.normalizeAssignTo(this.taskData.assignTo || (this.taskData.assigneeName ? 'mentor' : ''));
        this.selectedMentor = this.taskData.assigneeId || this.taskData.mentorId || '';
        this.descriptionHtml = this.taskData.descriptionHtml || this.taskData.description || '';

        if (!this.selectedMentor && this.taskData.assigneeName && Array.isArray(this.assigneeOptions)) {
            const matched = this.assigneeOptions.find((opt) => opt.label === this.taskData.assigneeName);
            if (matched) {
                this.selectedMentor = matched.value;
            }
        }
    }

    normalizeAssignTo(value) {
        const normalized = (value || '').toString().trim().toLowerCase();
        if (normalized === 'mentor' || normalized === 'mentee') {
            return normalized;
        }
        return '';
    }

    normalizeDate(value) {
        if (!value) return '';
        if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return '';
        return d.toISOString().slice(0, 10);
    }

    handleTitleChange(event) {
        const value = event.detail.value || '';
        this.title = value.length > TITLE_MAX_LENGTH ? value.slice(0, TITLE_MAX_LENGTH) : value;
        if (this.errors.title) {
            this.errors = { ...this.errors, title: '' };
        }
    }

    handleEndDateChange(event) {
        this.endDate = event.detail.value;
        if (this.errors.endDate) {
            this.errors = { ...this.errors, endDate: '' };
        }
    }

    handleStatusChange(event) {
        this.status = event.detail.value;
        if (this.errors.status) {
            this.errors = { ...this.errors, status: '' };
        }
    }

    handlePriorityChange(event) {
        this.priority = event.detail.value;
    }

    handleAssignToChange(event) {
        this.assignTo = this.normalizeAssignTo(event.detail?.value || event.target?.value || '');
        this.selectedMentor = '';
        if (this.errors.assignTo || this.errors.assignee) {
            this.errors = { ...this.errors, assignTo: '', assignee: '' };
        }
    }

    handleMentorChange(event) {
        this.selectedMentor = event.detail.value;
        if (this.errors.assignee) {
            this.errors = { ...this.errors, assignee: '' };
        }
    }

    handleRichTextInput(event) {
        this.descriptionHtml = event.target.innerHTML || '';
        setTimeout(() => {
            this.updateButtonStates();
        }, 50);
    }

    handleRichTextFocus(event) {
        setTimeout(() => {
            this.updateButtonStates();
        }, 50);
    }

    handleRichTextBlur(event) {
        this.descriptionHtml = event.target.innerHTML || '';
    }

    handleDescriptionChange(event) {
        this.descriptionHtml = event.detail.value || '';
    }

    _plainFromHtml(html) {
        const helper = document.createElement('div');
        helper.innerHTML = html || '';
        return (helper.textContent || '').trim();
    }

    handleRichTextSelection() {
        setTimeout(() => {
            this.updateButtonStates();
        }, 50);
    }

    updateButtonStates() {
        if (!this.richTextEditor) return;
        
        try {
            this.isBoldActive = document.queryCommandState('bold');
            this.isItalicActive = document.queryCommandState('italic');
            
            const selection = window.getSelection();
            let isInUnorderedList = false;
            let isInOrderedList = false;
            
            if (selection.rangeCount > 0) {
                const range = selection.getRangeAt(0);
                let container = range.commonAncestorContainer;
                
                while (container && container !== this.richTextEditor) {
                    if (container.nodeType === 1) {
                        const tagName = container.tagName.toUpperCase();
                        if (tagName === 'UL') {
                            isInUnorderedList = true;
                            break;
                        } else if (tagName === 'OL') {
                            isInOrderedList = true;
                            break;
                        } else if (tagName === 'LI') {
                            const parent = container.parentElement;
                            if (parent) {
                                const parentTag = parent.tagName.toUpperCase();
                                if (parentTag === 'UL') {
                                    isInUnorderedList = true;
                                } else if (parentTag === 'OL') {
                                    isInOrderedList = true;
                                }
                            }
                            break;
                        }
                    }
                    container = container.parentElement || container.parentNode;
                }
            }
            
            if (!isInUnorderedList && !isInOrderedList) {
                const lists = this.richTextEditor.querySelectorAll('ul, ol');
                if (lists.length > 0) {
                    const selection = window.getSelection();
                    if (selection.rangeCount > 0) {
                        const range = selection.getRangeAt(0);
                        lists.forEach(list => {
                            if (list.contains(range.commonAncestorContainer)) {
                                if (list.tagName.toUpperCase() === 'UL') {
                                    isInUnorderedList = true;
                                } else if (list.tagName.toUpperCase() === 'OL') {
                                    isInOrderedList = true;
                                }
                            }
                        });
                    }
                }
            }
            
            this.isUnorderedListActive = isInUnorderedList;
            this.isOrderedListActive = isInOrderedList;
            
        } catch (e) {
            console.error('Error updating button states:', e);
        }
    }

    executeCommand(command) {
        if (!this.richTextEditor) return;
        
        this.richTextEditor.focus();
        
        if (command === 'insertUnorderedList' || command === 'insertOrderedList') {
            const selection = window.getSelection();
            if (selection.rangeCount === 0 || selection.isCollapsed) {
                const range = document.createRange();
                const textNode = this.richTextEditor.childNodes[0] || this.richTextEditor;
                range.setStart(textNode, 0);
                range.setEnd(textNode, textNode.textContent ? textNode.textContent.length : 0);
                selection.removeAllRanges();
                selection.addRange(range);
            }
        }
        
        const success = document.execCommand(command, false, null);
        
        setTimeout(() => {
            this.descriptionHtml = this.richTextEditor.innerHTML;
            this.updateButtonStates();
            
            if (command === 'insertUnorderedList' || command === 'insertOrderedList') {
                this.ensureListFormatting();
            }
        }, 50);
    }

    ensureListFormatting() {
        const lists = this.richTextEditor.querySelectorAll('ul, ol');
        lists.forEach(list => {
            if (!list.style.marginLeft) {
                list.style.marginLeft = '1.5rem';
                list.style.marginTop = '0.5rem';
                list.style.marginBottom = '0.5rem';
            }
        });
        
        const listItems = this.richTextEditor.querySelectorAll('li');
        listItems.forEach(li => {
            if (!li.style.marginBottom) {
                li.style.marginBottom = '0.25rem';
            }
        });
    }

    handleBold() {
        this.executeCommand('bold');
    }

    handleItalic() {
        this.executeCommand('italic');
    }

    handleUnorderedList() {
        this.executeCommand('insertUnorderedList');
    }

    handleOrderedList() {
        this.executeCommand('insertOrderedList');
    }

    handleAIContinue() {
        console.log('AI continue clicked');
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.handleClose();
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close', {
            bubbles: true,
            composed: true
        }));
    }

    handleSave() {
        const errors = { title: '', status: '', endDate: '', assignTo: '', assignee: '' };
        const trimmedTitle = (this.title || '').trim();

        if (!trimmedTitle) {
            errors.title = 'Title is required.';
        } else if (trimmedTitle.length > TITLE_MAX_LENGTH) {
            errors.title = `Title cannot exceed ${TITLE_MAX_LENGTH} characters.`;
        }

        if (!this.status) {
            errors.status = 'Status is required.';
        }

        if (this.endDate && this.endDate < this.minEndDate) {
            errors.endDate = 'End date cannot be in the past.';
        }

        if (!this.assignTo) {
            errors.assignTo = 'Please select Mentor or Mentee.';
        } else if (!this.selectedMentor) {
            errors.assignee = `Please choose a ${this.assignTo}.`;
        }

        this.errors = errors;

        if (errors.title || errors.status || errors.endDate || errors.assignTo || errors.assignee) {
            return;
        }

        const selectedAssignee = (this.assigneeOptions || []).find((opt) => opt.value === this.selectedMentor);
        const assigneeName = selectedAssignee?.label || this.taskData?.assigneeName || '';

        const taskData = {
            id: this.taskData?.id,
            title: this.title,
            endDate: this.endDate,
            status: this.status,
            priority: this.priority,
            description: this._plainFromHtml(this.descriptionHtml),
            descriptionHtml: this.descriptionHtml,
            assignTo: this.assignTo,
            mentorId: this.assignTo === 'mentor' ? this.selectedMentor : '',
            assigneeName,
            assigneeId: this.selectedMentor
        };

        this.dispatchEvent(new CustomEvent('savetask', {
            detail: taskData,
            bubbles: true,
            composed: true
        }));

        this.handleClose();
    }
}