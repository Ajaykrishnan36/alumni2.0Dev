import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

const TYPE_OPTIONS = [
    { label: 'Honors & Awards', value: 'Honors & Awards' },
    { label: 'Academic Achievements', value: 'Academic Achievements' },
    { label: 'Patents', value: 'Patents' },
    { label: 'Books Authored', value: 'Books Authored' },
    { label: 'Publications', value: 'Publications' },
    { label: 'Papers Presented', value: 'Papers Presented' },
    { label: 'Certifications', value: 'Certifications' }
];

const MONTH_OPTIONS = [
    { label: 'January', value: '01' }, { label: 'February', value: '02' }, { label: 'March', value: '03' },
    { label: 'April', value: '04' }, { label: 'May', value: '05' }, { label: 'June', value: '06' },
    { label: 'July', value: '07' }, { label: 'August', value: '08' }, { label: 'September', value: '09' },
    { label: 'October', value: '10' }, { label: 'November', value: '11' }, { label: 'December', value: '12' }
];

const STATUS_OPTIONS = [
    { label: 'Pending', value: 'Pending' },
    { label: 'Filed', value: 'Filed' },
    { label: 'Published', value: 'Published' },
    { label: 'Granted', value: 'Granted' }
];

const ROLE_OPTIONS = [
    { label: 'Author', value: 'Author' },
    { label: 'Co-Author', value: 'Co-Author' },
    { label: 'Editor', value: 'Editor' },
    { label: 'Contributor', value: 'Contributor' }
];

const PAPER_TYPE_OPTIONS = [
    { label: 'Oral Presentation', value: 'Oral Presentation' },
    { label: 'Poster Presentation', value: 'Poster Presentation' },
    { label: 'Keynote', value: 'Keynote' },
    { label: 'Workshop', value: 'Workshop' },
    { label: 'Other', value: 'Other' }
];

const FIELD_CONFIG = {
    'Honors & Awards': { titleLabel: 'Award Name', titlePlaceholder: 'e.g. Best Student Award', orgLabel: 'Awarded By', orgPlaceholder: 'e.g. Department of Computer Science' },
    'Academic Achievements': { titleLabel: 'Title', titlePlaceholder: 'e.g. University Rank Holder', orgLabel: 'Institution / Program', orgPlaceholder: 'e.g. B.Tech - Computer Science, XYZ University' },
    Patents: { titleLabel: 'Patent Title', titlePlaceholder: 'e.g. Smart Energy Monitoring System', orgLabel: 'Issuing Authority', orgPlaceholder: 'e.g. Indian Patent Office' },
    'Books Authored': { titleLabel: 'Book Title', titlePlaceholder: 'e.g. Introduction to Data Science', orgLabel: 'Publisher', orgPlaceholder: 'e.g. Pearson' },
    Publications: { titleLabel: 'Title', titlePlaceholder: 'e.g. AI-Based Traffic Prediction Model', orgLabel: 'Journal / Platform', orgPlaceholder: 'e.g. IEEE, Springer' },
    'Papers Presented': { titleLabel: 'Paper Title', titlePlaceholder: 'e.g. Blockchain in Healthcare', orgLabel: 'Event / Conference', orgPlaceholder: 'e.g. International Tech Conference 2024' },
    Certifications: { titleLabel: 'Certification Name', titlePlaceholder: 'e.g. AWS Certified Cloud Practitioner', orgLabel: 'Issued By', orgPlaceholder: 'e.g. Amazon Web Services' }
};

function buildYearOptions() {
    const years = [];
    const current = new Date().getFullYear();
    for (let y = current; y >= current - 60; y--) {
        years.push({ label: String(y), value: String(y) });
    }
    return years;
}

export default class KenAchievementInformationModal extends LightningElement {
    @api achievementData = null;
    @api modalTitleOverride = '';

    @track type = 'Honors & Awards';
    @track title = '';
    @track organization = '';
    @track dateMonth = '';
    @track dateYear = '';
    @track patentNumber = '';
    @track status = '';
    @track role = '';
    @track referenceUrl = '';
    @track paperType = '';
    @track description = '';
    @track errors = { type: '', title: '', patentNumber: '' };

    @track isBoldActive = false;
    @track isItalicActive = false;
    @track isUnorderedListActive = false;
    @track isOrderedListActive = false;

    typeOptions = TYPE_OPTIONS;
    monthOptions = MONTH_OPTIONS;
    yearOptions = buildYearOptions();
    statusOptions = STATUS_OPTIONS;
    roleOptions = ROLE_OPTIONS;
    paperTypeOptions = PAPER_TYPE_OPTIONS;

    richTextEditor = null;
    previousData = null;

    get modalTitle() {
        if (this.modalTitleOverride) return this.modalTitleOverride;
        return this.achievementData?.id ? 'Edit Achievement' : 'Add Achievement';
    }

    get config() {
        return FIELD_CONFIG[this.type] || FIELD_CONFIG['Honors & Awards'];
    }

    get showPatentFields() { return this.type === 'Patents'; }
    get showBooksFields() { return this.type === 'Books Authored'; }
    get showPublicationFields() { return this.type === 'Publications'; }
    get showPaperFields() { return this.type === 'Papers Presented'; }
    get showCertificationFields() { return this.type === 'Certifications'; }

    get descriptionPlaceholder() {
        if (this.showPatentFields) return 'Brief explanation of the invention';
        if (this.showBooksFields) return 'About the book';
        if (this.showPublicationFields || this.showPaperFields) return 'Summary or contribution';
        if (this.showCertificationFields) return 'What you learned';
        return 'What was this award for?';
    }

    get referenceLabel() {
        if (this.showBooksFields) return 'ISBN / URL (Optional)';
        if (this.showCertificationFields) return 'Credential URL (Optional)';
        return 'URL / DOI (Optional)';
    }

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {});
        this.loadData();
        this.previousData = JSON.stringify(this.achievementData || null);
    }

    renderedCallback() {
        const current = JSON.stringify(this.achievementData || null);
        if (current !== this.previousData) {
            this.loadData();
            this.previousData = current;
        }

        const editor = this.template.querySelector('.rich-text-area');
        if (editor) {
            if (editor !== this.richTextEditor) {
                this.richTextEditor = editor;
                editor.innerHTML = this.description || '';
            } else if (editor.innerHTML !== (this.description || '')) {
                editor.innerHTML = this.description || '';
            }
            this.ensureListFormatting();
        }
    }

    loadData() {
        const data = this.achievementData || {};
        this.type = data.type || 'Honors & Awards';
        this.title = data.title || '';
        this.organization = data.organization || '';
        this.dateMonth = data.dateMonth || '';
        this.dateYear = data.dateYear || '';
        this.patentNumber = data.patentNumber || '';
        this.status = data.status || '';
        this.role = data.role || '';
        this.referenceUrl = data.referenceUrl || '';
        this.paperType = data.paperType || '';
        this.description = data.description || '';
        this.errors = { type: '', title: '', patentNumber: '' };
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) this.handleClose();
    }

    handleModalClick(event) {
        event.stopPropagation();
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }

    handleSelect(event) {
        const source = event.currentTarget || event.target;
        const field = source?.dataset?.field;
        if (!field) {
            return;
        }
        this[field] = event.detail?.value;
        if (this.errors[field]) this.errors = { ...this.errors, [field]: '' };
    }

    handleInput(event) {
        const source = event.currentTarget || event.target;
        const field = source?.dataset?.field;
        const raw = event.detail?.value ?? source?.value ?? event.target?.value;
        if (!field) {
            return;
        }
        if (field === 'patentNumber') {
            this.patentNumber = String(raw || '').replace(/\D/g, '');
            if (source) {
                source.value = this.patentNumber;
            }
        } else {
            this[field] = (raw || '').replace(/\s{2,}/g, ' ');
        }
        if (this.errors[field]) this.errors = { ...this.errors, [field]: '' };
    }

    handleRichTextInput(event) {
        const rawHtml = event.target.innerHTML || '';
        this.description = String(rawHtml).replace(/\s{2,}/g, ' ');
        setTimeout(() => this.updateButtonStates(), 0);
    }

    handleRichTextFocus() {
        setTimeout(() => this.updateButtonStates(), 0);
    }

    handleRichTextSelection() {
        setTimeout(() => this.updateButtonStates(), 0);
    }

    handleRichTextBlur(event) {
        const rawHtml = event.target.innerHTML || '';
        this.description = String(rawHtml).replace(/\s{2,}/g, ' ').trim();
        if (this.richTextEditor) {
            this.richTextEditor.innerHTML = this.description;
        }
    }

    executeCommand(command) {
        if (!this.richTextEditor) return;
        this.richTextEditor.focus();
        if (command === 'insertUnorderedList' || command === 'insertOrderedList') {
            const selection = window.getSelection();
            if (selection && (selection.rangeCount === 0 || selection.isCollapsed)) {
                const range = document.createRange();
                const textNode = this.richTextEditor.childNodes[0] || this.richTextEditor;
                range.setStart(textNode, 0);
                range.setEnd(textNode, textNode.textContent ? textNode.textContent.length : 0);
                selection.removeAllRanges();
                selection.addRange(range);
            }
        }
        document.execCommand(command, false, null);
        this.description = this.richTextEditor.innerHTML || '';
        this.ensureListFormatting();
        setTimeout(() => this.updateButtonStates(), 0);
    }

    handleBold(event) { event.preventDefault(); this.executeCommand('bold'); }
    handleItalic(event) { event.preventDefault(); this.executeCommand('italic'); }
    handleUnorderedList(event) { event.preventDefault(); this.executeCommand('insertUnorderedList'); }
    handleOrderedList(event) { event.preventDefault(); this.executeCommand('insertOrderedList'); }

    updateButtonStates() {
        try {
            this.isBoldActive = document.queryCommandState('bold');
            this.isItalicActive = document.queryCommandState('italic');

            let isInUnorderedList = false;
            let isInOrderedList = false;
            const selection = window.getSelection();
            if (selection && selection.rangeCount > 0) {
                const range = selection.getRangeAt(0);
                let container = range.commonAncestorContainer;
                while (container && container !== this.richTextEditor) {
                    if (container.nodeType === 1) {
                        const tagName = container.tagName.toUpperCase();
                        if (tagName === 'UL') {
                            isInUnorderedList = true;
                            break;
                        }
                        if (tagName === 'OL') {
                            isInOrderedList = true;
                            break;
                        }
                        if (tagName === 'LI') {
                            const parent = container.parentElement;
                            if (parent) {
                                const parentTag = parent.tagName.toUpperCase();
                                if (parentTag === 'UL') isInUnorderedList = true;
                                if (parentTag === 'OL') isInOrderedList = true;
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
            // ignore
        }
    }

    ensureListFormatting() {
        if (!this.richTextEditor) return;
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

    get boldButtonClass() { return `toolbar-button ${this.isBoldActive ? 'active' : ''}`; }
    get italicButtonClass() { return `toolbar-button ${this.isItalicActive ? 'active' : ''}`; }
    get unorderedListButtonClass() { return `toolbar-button ${this.isUnorderedListActive ? 'active' : ''}`; }
    get orderedListButtonClass() { return `toolbar-button ${this.isOrderedListActive ? 'active' : ''}`; }

    get typeErrorClass() { return `custom-select${this.errors.type ? ' error' : ''}`; }
    get titleErrorClass() { return `custom-input${this.errors.title ? ' error' : ''}`; }

    validate() {
        const nextErrors = { type: '', title: '', patentNumber: '' };
        let isValid = true;

        if (!this.type) {
            nextErrors.type = 'Type is required';
            isValid = false;
        }
        if (!this.title || !this.title.trim()) {
            nextErrors.title = 'Title is required';
            isValid = false;
        }
        if (this.showPatentFields && this.patentNumber && !/^\d+$/.test(this.patentNumber)) {
            nextErrors.patentNumber = 'Application / Patent Number should contain only digits';
            isValid = false;
        }

        this.errors = nextErrors;
        return isValid;
    }

    handleDescriptionChange(event) {
        this.description = event.detail.value || '';
    }

    handleSave() {
        if (!this.validate()) return;

        if (this.richTextEditor) {
            this.description = this.richTextEditor.innerHTML || '';
        }

        this.dispatchEvent(new CustomEvent('save', {
            detail: {
                id: this.achievementData?.id || null,
                type: this.type,
                title: this.title.trim(),
                organization: (this.organization || '').trim(),
                dateMonth: this.dateMonth || null,
                dateYear: this.dateYear || null,
                description: (this.description || '').trim(),
                patentNumber: (this.patentNumber || '').trim(),
                status: this.status || null,
                role: this.role || null,
                referenceUrl: (this.referenceUrl || '').trim(),
                paperType: this.paperType || null
            },
            bubbles: true,
            composed: true
        }));
    }
}