import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

const EMPLOYMENT_TYPES_JSON = [
    { label: 'Full-time', value: 'Full-time' },
    { label: 'Part-time', value: 'Part-time' },
    { label: 'Contract', value: 'Contract' },
    { label: 'Internship', value: 'Internship' },
    { label: 'Freelance', value: 'Freelance' }
];

const MONTHS_JSON = [
    { label: 'January', value: '01' },
    { label: 'February', value: '02' },
    { label: 'March', value: '03' },
    { label: 'April', value: '04' },
    { label: 'May', value: '05' },
    { label: 'June', value: '06' },
    { label: 'July', value: '07' },
    { label: 'August', value: '08' },
    { label: 'September', value: '09' },
    { label: 'October', value: '10' },
    { label: 'November', value: '11' },
    { label: 'December', value: '12' }
];

function generateYearOptions() {
    const currentYear = new Date().getFullYear();
    const years = [];
    for (let i = currentYear; i >= currentYear - 50; i--) {
        years.push({ label: String(i), value: String(i) });
    }
    return years;
}

export default class KenCareerInformationModal extends LightningElement {
    @api careerData = null;
    /** Optional: e.g. "Add Experience" / "Edit Experience" to override default title */
    @api modalTitleOverride = '';

    @track jobTitle = '';
    @track organization = '';
    @track employmentType = '';
    @track employmentStatus = ''; // 'business' or 'organization'
    @track location = '';
    @track startMonth = '';
    @track startYear = '';
    @track endMonth = '';
    @track endYear = '';
    @track roleDescriptionHtml = '';
    @track isCurrentJob = false;
    @track isBoldActive = false;
    @track isItalicActive = false;
    @track isUnorderedListActive = false;
    @track isOrderedListActive = false;
    
    // Validation errors
    @track errors = {
        jobTitle: '',
        organization: '',
        startMonth: '',
        startYear: '',
        endMonth: '',
        endYear: '',
        dateRange: ''
    };

    employmentTypeOptions = EMPLOYMENT_TYPES_JSON;
    monthOptions = MONTHS_JSON;
    yearOptions = generateYearOptions();
    
    richTextEditor = null;
    styleElement = null;
    previousCareerData = null;

    get modalTitle() {
        if (this.modalTitleOverride) return this.modalTitleOverride;
        return this.careerData && this.careerData.id ? 'Edit Career Information' : 'Add Career Information';
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            console.log('Error getting primary color');
        });
        this.loadCareerData();
        this.previousCareerData = this.careerData ? JSON.stringify(this.careerData) : null;
    }

    sanitizeSpacesWhileTyping(value) {
        if (value === null || value === undefined) return '';
        // collapse only 2+ whitespace into single space, keep leading/trailing for typing
        return String(value).replace(/\s{2,}/g, ' ');
    }

    sanitizeSpacesFinal(value) {
        if (value === null || value === undefined) return '';
        // collapse 2+ into one and trim ends
        return String(value).replace(/\s{2,}/g, ' ').trim();
    }

    normalizeCareerFieldsFinal() {
        this.jobTitle = this.sanitizeSpacesFinal(this.jobTitle);
        this.organization = this.sanitizeSpacesFinal(this.organization);
        this.location = this.sanitizeSpacesFinal(this.location);
        this.roleDescriptionHtml = this.sanitizeSpacesFinal(this.roleDescriptionHtml);
    }

    renderedCallback() {
        // Reload data if careerData prop changes
        const currentData = this.careerData ? JSON.stringify(this.careerData) : null;
        if (currentData !== this.previousCareerData) {
            this.loadCareerData();
            this.previousCareerData = currentData;
        }

        // Setup rich text editor
        const editor = this.template.querySelector('.rich-text-area');
        if (editor) {
            if (editor !== this.richTextEditor) {
                this.richTextEditor = editor;
                if (this.roleDescriptionHtml && editor.innerHTML !== this.roleDescriptionHtml) {
                    editor.innerHTML = this.roleDescriptionHtml;
                }

                editor.addEventListener('keyup', () => this.updateButtonStates());
                editor.addEventListener('mouseup', () => this.updateButtonStates());
            } else if (this.roleDescriptionHtml && editor.innerHTML !== this.roleDescriptionHtml) {
                editor.innerHTML = this.roleDescriptionHtml;
            } else if (!this.roleDescriptionHtml && editor.innerHTML) {
                editor.innerHTML = '';
            }
            this.ensureListFormatting();
        }
        this.injectDropdownStyles();
    }

    disconnectedCallback() {
        if (this.styleElement && this.styleElement.parentNode) {
            this.styleElement.parentNode.removeChild(this.styleElement);
        }
    }

    injectDropdownStyles() {
        if (!this.styleElement) {
            this.styleElement = document.createElement('style');
            this.styleElement.setAttribute('data-component', 'career-info-dropdown-styles');
            document.head.appendChild(this.styleElement);
            
            this.styleElement.textContent = `
                .slds-listbox,
                .slds-dropdown {
                    background-color: #ffffff !important;
                }
                .slds-listbox__option,
                .slds-dropdown__item {
                    background-color: #ffffff !important;
                    border: none !important;
                    border-top: none !important;
                    border-bottom: none !important;
                    border-left: none !important;
                    border-right: none !important;
                    box-shadow: none !important;
                }
                .slds-listbox__option:hover,
                .slds-dropdown__item:hover {
                    background-color: #f3f4f6 !important;
                    border: none !important;
                    border-top: none !important;
                    border-bottom: none !important;
                    border-left: none !important;
                    border-right: none !important;
                    outline: none !important;
                    box-shadow: none !important;
                }
                .slds-listbox__option[aria-selected="true"],
                .slds-dropdown__item[aria-selected="true"] {
                    background-color: #ffffff !important;
                    border: none !important;
                    border-top: none !important;
                    border-bottom: none !important;
                    border-left: none !important;
                    border-right: none !important;
                    box-shadow: none !important;
                }
                .slds-listbox__option *,
                .slds-dropdown__item *,
                .slds-listbox__option:hover *,
                .slds-dropdown__item:hover * {
                    border: none !important;
                    border-top: none !important;
                    border-bottom: none !important;
                    border-left: none !important;
                    border-right: none !important;
                    box-shadow: none !important;
                }
            `;
        }
    }

    loadCareerData() {
        // Clear errors when loading data
        this.errors = {
            jobTitle: '',
            organization: '',
            startMonth: '',
            startYear: '',
            endMonth: '',
            endYear: '',
            dateRange: ''
        };

        if (this.careerData) {
            this.jobTitle = this.careerData.jobTitle || '';
            this.organization = this.careerData.organization || '';
            this.employmentType = this.careerData.employmentType || '';
            this.employmentStatus = this.careerData.employmentStatus || '';
            this.location = this.careerData.location || '';
            this.employmentStatus = this.careerData.jobRole || '';


            // Parse start date
            if (this.careerData.startDate) {
                const startDate = new Date(this.careerData.startDate);
                this.startMonth = String(startDate.getMonth() + 1).padStart(2, '0');
                this.startYear = String(startDate.getFullYear());
            } else {
                this.startMonth = '';
                this.startYear = '';
            }
            
            // Parse end date
            if (this.careerData.endDate) {
                const endDate = new Date(this.careerData.endDate);
                this.endMonth = String(endDate.getMonth() + 1).padStart(2, '0');
                this.endYear = String(endDate.getFullYear());
            } else {
                this.endMonth = '';
                this.endYear = '';
            }
            
            this.roleDescriptionHtml = this.careerData.roleDescription || '';
            this.isCurrentJob = this.careerData.isCurrentJob || false;
        } else {
            // Reset to empty when adding new
            this.jobTitle = '';
            this.organization = '';
            this.employmentType = '';
            this.employmentStatus = '';
            this.location = '';
            this.startMonth = '';
            this.startYear = '';
            this.endMonth = '';
            this.endYear = '';
            this.roleDescriptionHtml = '';
            this.isCurrentJob = false;
        }

        this.normalizeCareerFieldsFinal();
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        const rawValue = event.target.value;

        const fieldsToSanitize = new Set(['jobTitle', 'organization', 'location']);

        if (fieldsToSanitize.has(field)) {
            // While typing: allow one space, remove only continuous spaces (2+)
            const cleaned = this.sanitizeSpacesWhileTyping(rawValue);

            if (cleaned !== rawValue) {
                event.target.value = cleaned;
            }
            this[field] = cleaned;
        } else {
            this[field] = rawValue;
        }

        // Clear error when user starts typing
        if (this.errors[field]) {
            this.errors = { ...this.errors, [field]: '' };
        }
    }

    handleSelectChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.detail.value;
    }

    handleEmploymentStatusChange(event) {
        const value = event.currentTarget.dataset.status; // picklist value
        this.employmentStatus = value;

        if (this.errors.employmentStatus) {
            this.errors = { ...this.errors, employmentStatus: '' };
        }
    }


    handleDateChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.detail.value;
        // Clear errors when user selects a date
        if (this.errors[field]) {
            this.errors = { ...this.errors, [field]: '' };
        }
        if (this.errors.dateRange) {
            this.errors = { ...this.errors, dateRange: '' };
        }
    }

    handleCheckboxChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.checked;
        if (this.isCurrentJob) {
            this.endMonth = '';
            this.endYear = '';
            // Clear end date errors when current job is checked
            this.errors = { ...this.errors, endMonth: '', endYear: '', dateRange: '' };
        }
    }

    handleRichTextInput(event) {
        const rawHtml = event.target.innerHTML || '';
        const cleaned = this.sanitizeSpacesWhileTyping(rawHtml);

        this.roleDescriptionHtml = cleaned;

        // Reflect back if user entered 2+ spaces
        if (cleaned !== rawHtml) {
            event.target.innerHTML = cleaned;
        }

        setTimeout(() => {
            this.updateButtonStates();
        }, 50);
    }

    handleRichTextFocus() {
        setTimeout(() => {
            this.updateButtonStates();
        }, 50);
    }
    
    handleRichTextSelection() {
        setTimeout(() => {
            this.updateButtonStates();
        }, 50);
    }

    handleRichTextBlur(event) {
        const rawHtml = event.target.innerHTML || '';
        const cleanedFinal = this.sanitizeSpacesFinal(rawHtml);

        this.roleDescriptionHtml = cleanedFinal;

        // Reflect final cleaned content
        if (cleanedFinal !== rawHtml) {
            event.target.innerHTML = cleanedFinal;
        }
    }

    updateButtonStates() {
        if (!this.richTextEditor) return;
        
        try {
            // Always check command states if editor exists
            this.isBoldActive = document.queryCommandState('bold');
            this.isItalicActive = document.queryCommandState('italic');
            
            // Check for list formatting - look at current selection or cursor position
            const selection = window.getSelection();
            let isInUnorderedList = false;
            let isInOrderedList = false;
            
            if (selection.rangeCount > 0) {
                const range = selection.getRangeAt(0);
                let container = range.commonAncestorContainer;
                
                // Traverse up to find list element
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
                                }
                                if (parentTag === 'OL') {
                                    isInOrderedList = true;
                                }
                            }
                            break;
                        }
                    }
                    container = container.parentElement || container.parentNode;
                }
            }

            this.isUnorderedListActive = isInUnorderedList;
            this.isOrderedListActive = isInOrderedList;

        } catch (e) {
            // swallow
        }
    }

    executeCommand(command) {
        if (!this.richTextEditor) return;
        
        this.richTextEditor.focus();
        
        // For list commands, ensure we're working with the selection
        if (command === 'insertUnorderedList' || command === 'insertOrderedList') {
            const selection = window.getSelection();
            if (selection.rangeCount === 0 || selection.isCollapsed) {
                // If no selection or collapsed, select the current line or create a list item
                const range = document.createRange();
                const textNode = this.richTextEditor.childNodes[0] || this.richTextEditor;
                range.setStart(textNode, 0);
                range.setEnd(textNode, textNode.textContent ? textNode.textContent.length : 0);
                selection.removeAllRanges();
                selection.addRange(range);
            }
        }

        document.execCommand(command, false, null);

        setTimeout(() => {
            // keep html synced; don't trim here, user might still type
            this.roleDescriptionHtml = this.richTextEditor.innerHTML || '';
            this.updateButtonStates();

            if (command === 'insertUnorderedList' || command === 'insertOrderedList') {
                this.ensureListFormatting();
            }
        }, 50);
    }
    
    ensureListFormatting() {
        const lists = this.richTextEditor ? this.richTextEditor.querySelectorAll('ul, ol') : [];
        lists.forEach(list => {
            if (!list.style.marginLeft) {
                list.style.marginLeft = '1.5rem';
                list.style.marginTop = '0.5rem';
                list.style.marginBottom = '0.5rem';
            }
        });

        const listItems = this.richTextEditor ? this.richTextEditor.querySelectorAll('li') : [];
        listItems.forEach(li => {
            if (!li.style.marginBottom) {
                li.style.marginBottom = '0.25rem';
            }
        });
    }

    handleBold(event) {
        event.preventDefault();
        this.executeCommand('bold');
    }

    handleItalic(event) {
        event.preventDefault();
        this.executeCommand('italic');
    }

    handleUnorderedList(event) {
        event.preventDefault();
        this.executeCommand('insertUnorderedList');
    }

    handleOrderedList(event) {
        event.preventDefault();
        this.executeCommand('insertOrderedList');
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

    get jobTitleErrorClass() {
        return `custom-input ${this.errors.jobTitle ? 'error' : ''}`;
    }

    get organizationErrorClass() {
        return `custom-input ${this.errors.organization ? 'error' : ''}`;
    }

   get businessButtonClass() {
        return `employment-status-button ${this.employmentStatus === 'Running my own Business' ? 'active' : ''}`;
    }

    get organizationButtonClass() {
        return `employment-status-button ${this.employmentStatus === 'Working at an Organization' ? 'active' : ''}`;
    }

    get startMonthErrorClass() {
        return `custom-select date-select ${this.errors.startMonth ? 'error' : ''}`;
    }

    get startYearErrorClass() {
        return `custom-select date-select ${this.errors.startYear ? 'error' : ''}`;
    }

    get endMonthErrorClass() {
        return `custom-select date-select ${this.errors.endMonth ? 'error' : ''}`;
    }

    get endYearErrorClass() {
        return `custom-select date-select ${this.errors.endYear ? 'error' : ''}`;
    }

    handleAIContinue() {
        console.log('AI Continue clicked');
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
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }

    validateForm() {
        this.normalizeCareerFieldsFinal();

        let isValid = true;
        const newErrors = {
            jobTitle: '',
            organization: '',
            startMonth: '',
            startYear: '',
            endMonth: '',
            endYear: '',
            dateRange: ''
        };

        // Validate Job Title
        if (!this.jobTitle || this.jobTitle.trim() === '') {
            newErrors.jobTitle = 'Job Title is required';
            isValid = false;
        }

        // Validate Organization
        if (!this.organization || this.organization.trim() === '') {
            newErrors.organization = 'Company / Organization is required';
            isValid = false;
        }

        // Validate Start Date
        if (!this.startMonth) {
            newErrors.startMonth = 'Start month is required';
            isValid = false;
        }
        if (!this.startYear) {
            newErrors.startYear = 'Start year is required';
            isValid = false;
        }

        // Validate End Date (if not current job)
        if (!this.isCurrentJob) {
            if (!this.endMonth) {
                newErrors.endMonth = 'End month is required';
                isValid = false;
            }
            if (!this.endYear) {
                newErrors.endYear = 'End year is required';
                isValid = false;
            }

            // Validate date range (end date should be after start date)
            if (this.startMonth && this.startYear && this.endMonth && this.endYear) {
                const startDate = new Date(parseInt(this.startYear, 10), parseInt(this.startMonth, 10) - 1);
                const endDate = new Date(parseInt(this.endYear, 10), parseInt(this.endMonth, 10) - 1);

                if (endDate < startDate) {
                    newErrors.dateRange = 'End date must be after start date';
                    isValid = false;
                }
            }
        }

        this.errors = newErrors;
        return isValid;
    }

    handleRoleDescriptionChange(event) {
        this.roleDescriptionHtml = event.detail.value || '';
    }

    handleSave() {
        // Validate form
        if (!this.validateForm()) {
            // Scroll to first error
            this.scrollToFirstError();
            return;
        }

        // Build start date
        const startDate = `${this.startYear}-${this.startMonth}-01`;
        
        // Build end date
        let endDate = null;
        if (!this.isCurrentJob && this.endMonth && this.endYear) {
            endDate = `${this.endYear}-${this.endMonth}-01`;
        }

        // Get HTML content from rich text editor
        if (this.richTextEditor) {
            const rawHtml = this.richTextEditor.innerHTML || '';
            this.roleDescriptionHtml = this.sanitizeSpacesFinal(rawHtml);
            this.richTextEditor.innerHTML = this.roleDescriptionHtml;
        }

        this.normalizeCareerFieldsFinal();

        const careerInfo = {
            jobTitle: this.jobTitle,
            organization: this.organization,
            employmentType: this.employmentType,
            location: this.location,
            startDate: startDate,
            endDate: endDate,
            roleDescription: this.roleDescriptionHtml,
            isCurrentJob: this.isCurrentJob,
            jobRole: this.employmentStatus
        };

        this.dispatchEvent(new CustomEvent('save', {
            detail: careerInfo,
            bubbles: true,
            composed: true
        }));
    }

    scrollToFirstError() {
        // Find first field with error and scroll to it
        const errorFields = ['jobTitle', 'organization', 'startMonth', 'startYear', 'endMonth', 'endYear'];
        for (const field of errorFields) {
            if (this.errors[field]) {
                const element = this.template.querySelector(`[data-field="${field}"]`);
                if (element) {
                    element.scrollIntoView({ behavior: 'smooth', block: 'center' });
                    element.focus();
                    break;
                }
            }
        }
    }
}