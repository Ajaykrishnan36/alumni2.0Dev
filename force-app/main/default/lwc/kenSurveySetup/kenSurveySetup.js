import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
export default class KenSurveySetup extends LightningElement {
    // Existing props
    @api surveyQuestions = [];
    @api surveyMandatory = false;
    @api surveyTypeOptions = [];

    // New state: Offer Meals
    @track offerMealsEnabled = false;
    @track mealsByDate = [];
    @track mealsPaidAddonEnabled = false;

    // New state: Dietary Preferences
    @track dietaryEnabled = false;
    @track dietaryOptions = {
        vegetarian: false,
        vegan: false,
        eggetarian: false,
        nonVegetarian: false,
        jain: false
    };

    // New state: Custom Survey
    @track customSurveyEnabled = false;

    // Backing store for eventSessionDates (public API via getter/setter below)
    _eventSessionDates = [];
    _eventSessionDatesSignature = '';

    // Computed properties
    get infoBannerText() {
        if (this.offerMealsEnabled) {
            return "This survey will appear during event registration to collect attendees' food preferences.";
        }
        return "This survey will appear during event registration to collect attendee preferences.";
    }

    get allMealsSelected() {
        if (this.mealsByDate.length === 0) return false;
        return this.mealsByDate.every(mealDate => 
            mealDate.breakfast && mealDate.lunch && mealDate.snacks && mealDate.dinner
        );
    }

    get someMealsSelected() {
        if (this.mealsByDate.length === 0) return false;
        const hasSome = this.mealsByDate.some(mealDate => 
            mealDate.breakfast || mealDate.lunch || mealDate.snacks || mealDate.dinner
        );
        const allSelected = this.allMealsSelected;
        return hasSome && !allSelected;
    }

    get hasMealDates() {
        return this.mealsByDate && this.mealsByDate.length > 0;
    }

    // Lifecycle hooks
    connectedCallback() {
        // Don't auto-build the table until the section is enabled; avoids unnecessary renders.
        // When enabled, we build from the latest eventSessionDates.
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);  
        }).catch(() => {
            document.documentElement.style.setProperty('--primary-color', '#B7202E');
            document.documentElement.style.setProperty('--secondary-color', '#E9BABE');
            document.documentElement.style.setProperty('--tertiary-color', '#F8E9EA');
        });
    }

    renderedCallback() {
        // Set indeterminate state for select-all checkbox
        const selectAllCheckbox = this.template.querySelector('#select-all-meals');
        if (selectAllCheckbox) {
            selectAllCheckbox.indeterminate = this.someMealsSelected;
        }
        
        // Set selected option for question type dropdowns
        this.template.querySelectorAll('select[data-question-id]').forEach(select => {
            const questionId = select.dataset.questionId;
            const question = this.surveyQuestions.find(q => q.id === questionId);
            if (question && question.type) {
                select.value = question.type;
            }
        });
    }

    // Public API: event session dates from parent (Step 2/3 flow)
    @api
    get eventSessionDates() {
        return this._eventSessionDates;
    }
    set eventSessionDates(value) {
        const next = Array.isArray(value) ? value : [];
        const nextSignature = this.buildDatesSignature(next);

        // Guard against reassigning same value (prevents render loops)
        if (nextSignature === this._eventSessionDatesSignature) {
            this._eventSessionDates = next;
            return;
        }

        this._eventSessionDates = next;
        this._eventSessionDatesSignature = nextSignature;

        // Only (re)build the table when the Meals section is enabled.
        if (this.offerMealsEnabled) {
            this.initializeMealsFromDates();
        }
    }

    // Initialize meals data from event session dates
    initializeMealsFromDates() {
        if (!this.eventSessionDates || this.eventSessionDates.length === 0) {
            this.mealsByDate = [];
            return;
        }

        // Extract distinct ISO dates from eventSessionDates
        // eventSessionDates comes from parent as array of {key, value, display} objects
        const distinctDates = [...new Set(this.eventSessionDates.map(d => {
            // Extract ISO date (YYYY-MM-DD) from key or value
            const dateStr = d.key || d.value || d;
            // Remove time portion if present
            return typeof dateStr === 'string' ? dateStr.split('T')[0] : dateStr;
        }))].sort(); // Sort ascending

        // Create meal objects, preserving existing selections
        const existingMap = new Map(this.mealsByDate.map(m => [m.dateISO, m]));
        
        this.mealsByDate = distinctDates.map(dateISO => {
            // Preserve existing selections if date already exists
            const existing = existingMap.get(dateISO);
            if (existing) {
                return existing;
            }

            // Find display label from original eventSessionDates
            const originalDate = this.eventSessionDates.find(d => {
                const dKey = d.key || d.value || d;
                const dISO = typeof dKey === 'string' ? dKey.split('T')[0] : dKey;
                return dISO === dateISO;
            });

            // Format date label (e.g., "12 Dec, 2026")
            let dateLabel;
            if (originalDate && originalDate.display) {
                dateLabel = originalDate.display;
            } else {
                // Fallback: format from ISO date
                const date = new Date(dateISO + 'T00:00:00');
                const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                const day = date.getDate();
                const month = months[date.getMonth()];
                const year = date.getFullYear();
                dateLabel = `${day} ${month}, ${year}`;
            }

            return {
                dateISO: dateISO,
                dateLabel: dateLabel,
                breakfast: false,
                lunch: false,
                snacks: false,
                dinner: false,
                rowSelected: false
            };
        });
    }

    buildDatesSignature(dates) {
        // Normalize to sorted distinct ISO dates so signature is stable
        const normalized = [...new Set((dates || []).map(d => {
            const dateStr = d?.key || d?.value || d;
            return typeof dateStr === 'string' ? dateStr.split('T')[0] : String(dateStr || '');
        }).filter(Boolean))].sort();
        return normalized.join('|');
    }

    // Event Handlers: Offer Meals
    handleToggleOfferMeals(event) {
        this.offerMealsEnabled = event.target.checked;
        if (this.offerMealsEnabled) {
            this.initializeMealsFromDates();
        }
        this.dispatchChange();
    }

    handleSelectAllMeals(event) {
        const checked = event.target.checked;
        this.mealsByDate = this.mealsByDate.map(mealDate => ({
            ...mealDate,
            breakfast: checked,
            lunch: checked,
            snacks: checked,
            dinner: checked,
            rowSelected: checked
        }));
        // Force reactivity update
        this.mealsByDate = [...this.mealsByDate];
        this.dispatchChange();
    }

    handleSelectRowMeals(event) {
        const dateISO = event.currentTarget.dataset.dateIso;
        const checked = event.target.checked;
        this.mealsByDate = this.mealsByDate.map(mealDate => {
            if (mealDate.dateISO === dateISO) {
                return {
                    ...mealDate,
                    breakfast: checked,
                    lunch: checked,
                    snacks: checked,
                    dinner: checked,
                    rowSelected: checked
                };
            }
            return mealDate;
        });
        // Force reactivity update
        this.mealsByDate = [...this.mealsByDate];
        this.dispatchChange();
    }

    handleMealCheckboxChange(event) {
        const dateISO = event.currentTarget.dataset.dateIso;
        const meal = event.currentTarget.dataset.meal;
        const checked = event.target.checked;

        this.mealsByDate = this.mealsByDate.map(mealDate => {
            if (mealDate.dateISO === dateISO) {
                const updated = { ...mealDate, [meal]: checked };
                // Update rowSelected based on all meals
                updated.rowSelected = updated.breakfast && updated.lunch && updated.snacks && updated.dinner;
                return updated;
            }
            return mealDate;
        });
        // Force reactivity update
        this.mealsByDate = [...this.mealsByDate];
        this.dispatchChange();
    }

    handleToggleMealsPaid(event) {
        this.mealsPaidAddonEnabled = event.target.checked;
        this.dispatchChange();
    }

    // Event Handlers: Dietary Preferences
    handleToggleDietary(event) {
        this.dietaryEnabled = event.target.checked;
        this.dispatchChange();
    }

    handleDietaryOptionChange(event) {
        const option = event.currentTarget.dataset.option;
        this.dietaryOptions = {
            ...this.dietaryOptions,
            [option]: event.target.checked
        };
        this.dispatchChange();
    }

    // Event Handlers: Custom Survey
    handleToggleCustomSurvey(event) {
        this.customSurveyEnabled = event.target.checked;
        this.dispatchChange();
    }

    // ----- Custom Survey (createSurvey-like builder) -----
    get questionTypeOptions() {
        // Reuse parent-provided options; fallback to sane defaults
        return (this.surveyTypeOptions && this.surveyTypeOptions.length)
            ? this.surveyTypeOptions
            : [
                { label: 'Single Select', value: 'Multiple Choice' },
                { label: 'Checkbox', value: 'Yes/No' },
                { label: 'Linear scale', value: 'linear' },
                { label: 'Short answer', value: 'Short Answer' }
            ];
    }

    get scaleNumberOptions() {
        const options = [];
        for (let i = 1; i <= 5; i++) {
            options.push({ label: i.toString(), value: i.toString() });
        }
        return options;
    }

    get questions() {
        // Adapt the existing surveyQuestions shape to the UI shape used by createSurvey.html
        const qs = Array.isArray(this.surveyQuestions) ? this.surveyQuestions : [];
        return qs.map((q, idx) => {
            const type = q.type || 'Multiple Choice';
            const normalizedType = String(type).toLowerCase();
            const isMultiple = normalizedType === 'multiple' || normalizedType === 'multiple choice';
            const isShortAnswer = normalizedType === 'short' || normalizedType === 'short answer';
            const isCheckboxType = normalizedType === 'checkbox' || normalizedType === 'yes/no';
            const isDropdownType = normalizedType === 'dropdown';
            const isLinear = normalizedType === 'linear' || normalizedType === 'linear scale';
            const showMultipleOptions = isMultiple || isCheckboxType || isDropdownType;
            const showLinearScale = isLinear;
            const options = (q.options || []).map((opt, optIdx) => ({
                id: opt.id,
                text: opt.text,
                letter: opt.letter || String.fromCharCode(97 + optIdx)
            }));
            return {
                ...q,
                number: q.number || idx + 1,
                type,
                required: !!q.required,
                options,
                showMultipleOptions,
                showLinearScale,
                isMultiple,
                isCheckboxType,
                nextOptionNumber: (options.length || 0) + 1,
                scaleMin: q.scaleMin != null ? String(q.scaleMin) : '1',
                scaleMax: q.scaleMax != null ? String(q.scaleMax) : '5',
                scaleMinLabel: q.scaleMinLabel || '',
                scaleMaxLabel: q.scaleMaxLabel || ''
            };
        });
    }

    handleAddQuestion() {
        this.dispatchEvent(new CustomEvent('addquestion', { bubbles: true, composed: true }));
    }

    handleDeleteQuestion(event) {
        const questionId = event.currentTarget.dataset.questionId;
        this.dispatchEvent(new CustomEvent('removequestion', {
            detail: { questionId },
            bubbles: true,
            composed: true
        }));
    }

    handleQuestionTextChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value;
        this.dispatchEvent(new CustomEvent('questionchange', {
            detail: { questionId, value },
            bubbles: true,
            composed: true
        }));
    }

    handleQuestionTypeChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value;
        this.dispatchEvent(new CustomEvent('typechange', {
            detail: { questionId, value },
            bubbles: true,
            composed: true
        }));
    }

    handleRequiredToggle(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.target.checked;
        this.dispatchEvent(new CustomEvent('questionrequiredchange', {
            detail: { questionId, value },
            bubbles: true,
            composed: true
        }));
    }

    handleOptionTextChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const optionId = event.currentTarget.dataset.optionId;
        const value = event.detail?.value ?? event.target.value;
        this.dispatchEvent(new CustomEvent('optionchange', {
            detail: { questionId, optionId, value },
            bubbles: true,
            composed: true
        }));
    }

    handleAddOptionClick(event) {
        const questionId = event.currentTarget.dataset.questionId;
        this.dispatchEvent(new CustomEvent('addoption', {
            detail: { questionId },
            bubbles: true,
            composed: true
        }));
    }

    handleDeleteOption(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const optionId = event.currentTarget.dataset.optionId;
        this.dispatchEvent(new CustomEvent('removeoption', {
            detail: { questionId, optionId },
            bubbles: true,
            composed: true
        }));
    }

    handleScaleMinChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value;
        this.dispatchEvent(new CustomEvent('scalechange', {
            detail: { questionId, scaleMin: value || '1' },
            bubbles: true,
            composed: true
        }));
    }

    handleScaleMaxChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value;
        this.dispatchEvent(new CustomEvent('scalechange', {
            detail: { questionId, scaleMax: value || '5' },
            bubbles: true,
            composed: true
        }));
    }

    handleScaleMinLabelChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value;
        this.dispatchEvent(new CustomEvent('scalechange', {
            detail: { questionId, scaleMinLabel: value },
            bubbles: true,
            composed: true
        }));
    }

    handleScaleMaxLabelChange(event) {
        const questionId = event.currentTarget.dataset.questionId;
        const value = event.detail?.value ?? event.target.value;
        this.dispatchEvent(new CustomEvent('scalechange', {
            detail: { questionId, scaleMaxLabel: value },
            bubbles: true,
            composed: true
        }));
    }

    // Drag & drop reorder (HTML5)
    draggedQuestionId;

    handleDragStart(event) {
        const questionId = event.currentTarget.dataset.questionId;
        this.draggedQuestionId = questionId;
        event.dataTransfer.dropEffect = 'move';
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', questionId);
    }

    handleDragOver(event) {
        event.preventDefault();
        const el = event.currentTarget;
        el.classList.add('drag-over');
    }

    handleDragEnd(event) {
        const el = event.currentTarget;
        el.classList.remove('drag-over');
    }

    handleDrop(event) {
        event.preventDefault();
        const toQuestionId = event.currentTarget.dataset.questionId;
        const fromQuestionId = this.draggedQuestionId || event.dataTransfer.getData('text/plain');
        event.currentTarget.classList.remove('drag-over');

        if (!fromQuestionId || !toQuestionId || fromQuestionId === toQuestionId) return;

        this.dispatchEvent(new CustomEvent('reorderquestions', {
            detail: { fromQuestionId, toQuestionId },
            bubbles: true,
            composed: true
        }));
    }

    // Dispatch change event to parent
    dispatchChange() {
        this.dispatchEvent(new CustomEvent('surveychange', {
            detail: {
                offerMealsEnabled: this.offerMealsEnabled,
                mealsByDate: this.mealsByDate,
                mealsPaidAddonEnabled: this.mealsPaidAddonEnabled,
                dietaryEnabled: this.dietaryEnabled,
                dietaryOptions: this.dietaryOptions,
                customSurveyEnabled: this.customSurveyEnabled
            },
            bubbles: true,
            composed: true
        }));
    }

    // Public method to get current state (for validation)
    @api
    getSurveyState() {
        return {
            offerMealsEnabled: this.offerMealsEnabled,
            mealsByDate: this.mealsByDate,
            mealsPaidAddonEnabled: this.mealsPaidAddonEnabled,
            dietaryEnabled: this.dietaryEnabled,
            dietaryOptions: this.dietaryOptions,
            customSurveyEnabled: this.customSurveyEnabled,
            surveyQuestions: this.surveyQuestions
        };
    }
}