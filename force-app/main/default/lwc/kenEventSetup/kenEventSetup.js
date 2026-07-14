import { LightningElement, api, track } from 'lwc';
import aiStar from '@salesforce/resourceUrl/aiStar';

export default class KenEventSetup extends LightningElement {
    aiStarUrl = aiStar;
    _eventData = {};
    @api
    get eventData() {
        return this._eventData;
    }
    set eventData(value) {
        this._eventData = value || {};
        this.syncRichTextFromEventData();
    }
    @api validationErrors = {};
    @api selectedCategories = [];
    @api selectedSuitableFor = [];
    @api selectedLanguages = [];
    @api categoryOptions = [];
    @api suitableForOptions = [];
    @api languageOptions = [];
    @api showCategoryDropdown = false;
    @api showSuitableForDropdown = false;
    @api showLanguageDropdown = false;
    @api isPicklistDataLoaded = false;
    @api hasCoverPhoto = false;
    @api hasBrochureFile = false;
    @api selectedDates = [];
    @api currentDate;
    @api calendarDays = [];
    @api currentMonthYear = '';

    @track descriptionValue = '';
    @track agendaValue = '';
    @track expectationsValue = '';
    @track descriptionHtml = '';
    @track agendaHtml = '';
    @track expectationsHtml = '';
    @track canBringGuests = 'yes';
    @track maxGuestsPerParticipant = 1;

    get eventTitleClass() {
        return this.validationErrors.title ? 'form-input error' : 'form-input';
    }

    get maxParticipantsClass() {
        return this.validationErrors.maxParticipants ? 'form-input error' : 'form-input';
    }

    get descriptionClass() {
        return this.validationErrors.description ? 'form-input error' : 'form-input';
    }

    get agendaClass() {
        return this.validationErrors.agenda ? 'form-input error' : 'form-input';
    }

    get expectationsClass() {
        return this.validationErrors.expectations ? 'form-input error' : 'form-input';
    }

    get maxGuestsClass() {
        return this.validationErrors.maxGuestsPerParticipant ? 'form-input error stepper-input' : 'form-input stepper-input';
    }

    get canBringGuestsValue() {
        return this.canBringGuests === 'yes';
    }

    get canBringGuestsNoValue() {
        return this.canBringGuests === 'no';
    }

    get showMaxGuestsField() {
        return this.canBringGuests === 'yes';
    }

    connectedCallback() {
        this.syncRichTextFromEventData();
    }

    renderedCallback() {
        this.syncRichTextDom();
    }

    syncRichTextFromEventData() {
        const description = this._eventData?.description || '';
        const agenda = this._eventData?.agenda || '';
        const expectations = this._eventData?.expectations || '';
        this.descriptionValue = description;
        this.agendaValue = agenda;
        this.expectationsValue = expectations;
        this.descriptionHtml = description;
        this.agendaHtml = agenda;
        this.expectationsHtml = expectations;
        if (this._eventData?.canBringGuests) {
            this.canBringGuests = this._eventData.canBringGuests;
        }
        if (this._eventData?.maxGuestsPerParticipant !== undefined && this._eventData?.maxGuestsPerParticipant !== null) {
            this.maxGuestsPerParticipant = parseInt(this._eventData.maxGuestsPerParticipant, 10) || 0;
        }
        this.syncRichTextDom();
    }

    isRichTextEmpty(element) {
        return !element || !element.textContent || !element.textContent.trim();
    }

    syncRichTextDom() {
        if (!this.template) {
            return;
        }

        const fields = [
            { id: 'description', value: this._eventData?.description || '' },
            { id: 'agenda',      value: this._eventData?.agenda      || '' },
            { id: 'expectations',value: this._eventData?.expectations|| '' }
        ];

        for (const { id, value } of fields) {
            const div = this.template.querySelector(`[data-id="${id}"]`);
            if (!div) continue;
            if (this.template.activeElement === div) continue;
            if (div.innerHTML !== value) {
                div.innerHTML = value;
            }
        }
    }

    handleEventTitleChange(event) {
        const value = event.target.value;
        this.dispatchEvent(new CustomEvent('datachange', {
            detail: { field: 'title', value },
            bubbles: true,
            composed: true
        }));
    }

    handleMaxParticipantsChange(event) {
        const value = event.target.value;
        this.dispatchEvent(new CustomEvent('datachange', {
            detail: { field: 'maxParticipants', value },
            bubbles: true,
            composed: true
        }));
    }

    // Helper function to strip HTML and get plain text
    stripHtml(html) {
        const tmp = document.createElement('DIV');
        tmp.innerHTML = html;
        return tmp.textContent || tmp.innerText || '';
    }

    // Helper function to get plain text length
    getTextLength(html) {
        return this.stripHtml(html).length;
    }

    handleDescriptionChange(event) {
        const html = event.detail.value || '';
        const text = this.stripHtml(html);
        this.descriptionHtml = html;
        this.descriptionValue = text;
        this.dispatchEvent(new CustomEvent('datachange', {
            detail: { field: 'description', value: text, html },
            bubbles: true,
            composed: true
        }));
    }

    handleAgendaChange(event) {
        const html = event.detail.value || '';
        const text = this.stripHtml(html);
        this.agendaHtml = html;
        this.agendaValue = text;
        this.dispatchEvent(new CustomEvent('datachange', {
            detail: { field: 'agenda', value: text, html },
            bubbles: true,
            composed: true
        }));
    }

    handleExpectationsChange(event) {
        const html = event.detail.value || '';
        const text = this.stripHtml(html);
        this.expectationsHtml = html;
        this.expectationsValue = text;
        this.dispatchEvent(new CustomEvent('datachange', {
            detail: { field: 'expectations', value: text, html },
            bubbles: true,
            composed: true
        }));
    }

    handleDescriptionInput(event) {
        const html = event.target.innerHTML;
        const text = this.stripHtml(html);
        
        // Check character limit (500)
        if (text.length > 500) {
            event.preventDefault();
            const truncated = text.substring(0, 500);
            event.target.innerHTML = truncated;
            return;
        }
        
        this.descriptionHtml = html;
        this.descriptionValue = text;
        this.dispatchEvent(new CustomEvent('datachange', {
            detail: { field: 'description', value: text, html: html },
            bubbles: true,
            composed: true
        }));
    }

    handleDescriptionPaste(event) {
        event.preventDefault();
        const text = (event.clipboardData || window.clipboardData).getData('text/plain');
        document.execCommand('insertText', false, text);
    }

    handleDescriptionKeydown(event) {
        const html = event.target.innerHTML;
        const text = this.stripHtml(html);
        
        // Allow backspace, delete, arrow keys, etc.
        const allowedKeys = ['Backspace', 'Delete', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Tab'];
        if (allowedKeys.includes(event.key)) {
            return;
        }
        
        // Check character limit before allowing input
        if (text.length >= 500 && !event.ctrlKey && !event.metaKey) {
            event.preventDefault();
        }
    }

    handleAgendaInput(event) {
        const html = event.target.innerHTML;
        const text = this.stripHtml(html);
        
        // Check character limit (300)
        if (text.length > 300) {
            event.preventDefault();
            const truncated = text.substring(0, 300);
            event.target.innerHTML = truncated;
            return;
        }
        
        this.agendaHtml = html;
        this.agendaValue = text;
        this.dispatchEvent(new CustomEvent('datachange', {
            detail: { field: 'agenda', value: text, html: html },
            bubbles: true,
            composed: true
        }));
    }

    handleAgendaPaste(event) {
        event.preventDefault();
        const text = (event.clipboardData || window.clipboardData).getData('text/plain');
        document.execCommand('insertText', false, text);
    }

    handleAgendaKeydown(event) {
        const html = event.target.innerHTML;
        const text = this.stripHtml(html);
        
        // Allow backspace, delete, arrow keys, etc.
        const allowedKeys = ['Backspace', 'Delete', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Tab'];
        if (allowedKeys.includes(event.key)) {
            return;
        }
        
        // Check character limit before allowing input
        if (text.length >= 300 && !event.ctrlKey && !event.metaKey) {
            event.preventDefault();
        }
    }

    handleExpectationsInput(event) {
        const html = event.target.innerHTML;
        const text = this.stripHtml(html);

        // Check character limit (1000)
        if (text.length > 1000) {
            event.preventDefault();
            const truncated = text.substring(0, 1000);
            event.target.innerHTML = truncated;
            return;
        }

        this.expectationsHtml = html;
        this.expectationsValue = text;
        this.dispatchEvent(new CustomEvent('datachange', {
            detail: { field: 'expectations', value: text, html: html },
            bubbles: true,
            composed: true
        }));
    }

    handleExpectationsPaste(event) {
        event.preventDefault();
        const text = (event.clipboardData || window.clipboardData).getData('text/plain');
        document.execCommand('insertText', false, text);
    }

    handleExpectationsKeydown(event) {
        const html = event.target.innerHTML;
        const text = this.stripHtml(html);

        // Allow backspace, delete, arrow keys, etc.
        const allowedKeys = ['Backspace', 'Delete', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Tab'];
        if (allowedKeys.includes(event.key)) {
            return;
        }

        // Check character limit before allowing input
        if (text.length >= 1000 && !event.ctrlKey && !event.metaKey) {
            event.preventDefault();
        }
    }

    handleBold(event) {
        event.preventDefault();
        document.execCommand('bold', false, null);
        // Update the content after formatting
        const activeElement = document.activeElement;
        if (activeElement && activeElement.contentEditable === 'true') {
            if (activeElement.id === 'description') {
                this.handleDescriptionInput({ target: activeElement });
            } else if (activeElement.id === 'agenda') {
                this.handleAgendaInput({ target: activeElement });
            } else if (activeElement.id === 'expectations') {
                this.handleExpectationsInput({ target: activeElement });
            }
        }
    }

    handleItalic(event) {
        event.preventDefault();
        document.execCommand('italic', false, null);
        // Update the content after formatting
        const activeElement = document.activeElement;
        if (activeElement && activeElement.contentEditable === 'true') {
            if (activeElement.id === 'description') {
                this.handleDescriptionInput({ target: activeElement });
            } else if (activeElement.id === 'agenda') {
                this.handleAgendaInput({ target: activeElement });
            } else if (activeElement.id === 'expectations') {
                this.handleExpectationsInput({ target: activeElement });
            }
        }
    }

    handleList(event) {
        event.preventDefault();
        document.execCommand('insertUnorderedList', false, null);
        // Update the content after formatting
        const activeElement = document.activeElement;
        if (activeElement && activeElement.contentEditable === 'true') {
            if (activeElement.id === 'description') {
                this.handleDescriptionInput({ target: activeElement });
            } else if (activeElement.id === 'agenda') {
                this.handleAgendaInput({ target: activeElement });
            } else if (activeElement.id === 'expectations') {
                this.handleExpectationsInput({ target: activeElement });
            }
        }
    }

    handleCoverPhotoUploadScreen() {
        // Find the file input in this component and trigger it
        const fileInput = this.template.querySelector('input[type="file"][accept*="image"]');
        if (fileInput) {
            fileInput.click();
        }
    }

    handleCoverPhotoUpload(event) {
        const file = event.target.files[0];
        this.dispatchEvent(new CustomEvent('coverphotoupload', {
            detail: { file },
            bubbles: true,
            composed: true
        }));
    }

    handleDeleteCoverImage() {
        this.dispatchEvent(new CustomEvent('deletecoverimage', {
            bubbles: true,
            composed: true
        }));
    }

    handleBrochureUpload(event) {
        const file = event.target.files[0];
        this.dispatchEvent(new CustomEvent('brochureupload', {
            detail: { file },
            bubbles: true,
            composed: true
        }));
    }

    handleChangeBrochure() {
        this.dispatchEvent(new CustomEvent('changebrochure', {
            bubbles: true,
            composed: true
        }));
    }

    handleRemoveBrochure() {
        this.dispatchEvent(new CustomEvent('removebrochure', {
            bubbles: true,
            composed: true
        }));
    }

    handleBrochureChangeUpload(event) {
        const file = event.target.files[0];
        this.dispatchEvent(new CustomEvent('brochureupload', {
            detail: { file },
            bubbles: true,
            composed: true
        }));
    }

    handleCategoryDropdownToggle(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('categorytoggle', {
            bubbles: true,
            composed: true
        }));
    }

    handleCategorySelect(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value;
        this.dispatchEvent(new CustomEvent('categoryselect', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }

    handleRemoveCategory(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value;
        this.dispatchEvent(new CustomEvent('removecategory', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }

    handleSuitableForDropdownToggle(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('suitablefortoggle', {
            bubbles: true,
            composed: true
        }));
    }

    handleSuitableForSelect(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value;
        this.dispatchEvent(new CustomEvent('suitableforselect', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }

    handleRemoveSuitableFor(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value;
        this.dispatchEvent(new CustomEvent('removesuitablefor', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }

    handleLanguageDropdownToggle(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('languagetoggle', {
            bubbles: true,
            composed: true
        }));
    }

    handleLanguageSelect(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value;
        this.dispatchEvent(new CustomEvent('languageselect', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }

    handleRemoveLanguage(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.value;
        this.dispatchEvent(new CustomEvent('removelanguage', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }

    handleDropdownContainerClick(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('dropdownclick', {
            detail: { field: event.currentTarget.dataset.field },
            bubbles: true,
            composed: true
        }));
    }

    // Date Selection Handlers
    handleDateClick(event) {
        const date = event.currentTarget.dataset.date;
        this.dispatchEvent(new CustomEvent('datechange', {
            detail: { date },
            bubbles: true,
            composed: true
        }));
    }

    handleRemoveDate(event) {
        event.stopPropagation();
        const date = event.currentTarget.dataset.date;
        this.dispatchEvent(new CustomEvent('removedate', {
            detail: { date },
            bubbles: true,
            composed: true
        }));
    }

    handleCanBringGuestsChange(event) {
        const value = event.target.value;
        this.canBringGuests = value;
        this.dispatchEvent(new CustomEvent('datachange', {
            detail: { field: 'canBringGuests', value },
            bubbles: true,
            composed: true
        }));
    }

    handleMaxGuestsChange(event) {
        const value = parseInt(event.target.value, 10) || 0;
        this.maxGuestsPerParticipant = value;
        this.dispatchEvent(new CustomEvent('datachange', {
            detail: { field: 'maxGuestsPerParticipant', value },
            bubbles: true,
            composed: true
        }));
    }

    handleIncrementGuests(event) {
        event.preventDefault();
        this.maxGuestsPerParticipant = (this.maxGuestsPerParticipant || 0) + 1;
        this.dispatchEvent(new CustomEvent('datachange', {
            detail: { field: 'maxGuestsPerParticipant', value: this.maxGuestsPerParticipant },
            bubbles: true,
            composed: true
        }));
    }

    handleDecrementGuests(event) {
        event.preventDefault();
        if (this.maxGuestsPerParticipant > 0) {
            this.maxGuestsPerParticipant = this.maxGuestsPerParticipant - 1;
            this.dispatchEvent(new CustomEvent('datachange', {
                detail: { field: 'maxGuestsPerParticipant', value: this.maxGuestsPerParticipant },
                bubbles: true,
                composed: true
            }));
        }
    }

    handlePrevMonth() {
        this.dispatchEvent(new CustomEvent('monthchange', {
            detail: { direction: 'prev' },
            bubbles: true,
            composed: true
        }));
    }

    handleNextMonth() {
        this.dispatchEvent(new CustomEvent('monthchange', {
            detail: { direction: 'next' },
            bubbles: true,
            composed: true
        }));
    }
}