import { LightningElement, api, track } from 'lwc';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

const MEAL_COLUMNS = ['Breakfast', 'Lunch', 'Snacks', 'Dinner'];
const DIETARY_OPTIONS = ['Vegetarian', 'Vegan', 'Eggetarian', 'Non-Vegetarian', 'Jain'];

export default class KenPreEventSurvey extends LightningElement {
    _eventDates = [];

    @track offerMealsEnabled = false;
    @track mealsPaidAddonEnabled = false;
    @track dietaryEnabled = false;
    @track customSurveyEnabled = false;

    // internal: { 'YYYY-MM-DD': Set-like map { Breakfast:true, ... } }
    @track mealsByDate = {};
    @track selectedDietary = [];
    @track surveyQuestions = [];
    // When meals are offered, dietary preferences are required; this drives the inline error.
    @track dietaryError = '';
    // When the org has fees disabled, the "Make Meals Paid" add-on is hidden
    // (it would otherwise prompt for payment in a fee-less event).
    @track feeDisabled = false;

    _seeded = false;

    connectedCallback() {
        getPrimaryColor().then(color => {
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
            this.feeDisabled = color?.disableEventFee === true;
        }).catch(() => {});
    }

    get showMealsPaidAddon() {
        return !this.feeDisabled;
    }

    @api
    get eventDates() {
        return this._eventDates;
    }
    set eventDates(value) {
        this._eventDates = Array.isArray(value) ? value : [];
    }

    /** Seed initial state once (edit-mode resume). */
    @api
    get initialData() {
        return null;
    }
    set initialData(value) {
        if (!value || this._seeded) return;
        this._seeded = true;
        this.offerMealsEnabled = !!value.offerMealsEnabled;
        this.mealsPaidAddonEnabled = !!value.mealsPaidAddonEnabled;
        // Dietary is mandatory whenever meals are offered, so keep it on when resuming such an event.
        this.dietaryEnabled = this.offerMealsEnabled ? true : !!value.dietaryEnabled;
        this.customSurveyEnabled = !!value.customSurveyEnabled;
        this.selectedDietary = Array.isArray(value.dietaryOptions) ? [...value.dietaryOptions] : [];
        this.surveyQuestions = Array.isArray(value.surveyQuestions) ? value.surveyQuestions.map(q => ({ ...q })) : [];
        const seedMeals = {};
        const incoming = value.mealsByDate || {};
        Object.keys(incoming).forEach(dateKey => {
            const list = incoming[dateKey] || [];
            seedMeals[dateKey] = {};
            list.forEach(meal => { seedMeals[dateKey][meal] = true; });
        });
        this.mealsByDate = seedMeals;
    }

    get mealRows() {
        return (this._eventDates || []).map(d => {
            const dateKey = d.value || d.key;
            const selected = this.mealsByDate[dateKey] || {};
            const cells = MEAL_COLUMNS.map(meal => ({
                key: `${dateKey}-${meal}`,
                meal,
                checked: !!selected[meal]
            }));
            const allChecked = MEAL_COLUMNS.every(meal => selected[meal]);
            return {
                key: dateKey,
                dateKey,
                display: d.display || dateKey,
                cells,
                allChecked
            };
        });
    }

    get mealColumns() {
        return MEAL_COLUMNS;
    }

    get dietaryItems() {
        return DIETARY_OPTIONS.map(opt => ({
            label: opt,
            value: opt,
            checked: this.selectedDietary.includes(opt)
        }));
    }

    /* ---------- Offer Meals ---------- */
    handleOfferMealsToggle(event) {
        this.offerMealsEnabled = event.target.checked;
        if (this.offerMealsEnabled) {
            // Offering meals makes dietary preferences mandatory — turn the section on so the
            // attendee dietary options must be chosen before proceeding.
            this.dietaryEnabled = true;
        } else {
            this.mealsPaidAddonEnabled = false;
            this.dietaryEnabled = false;
            this.dietaryError = '';
        }
        this.emitChange();
    }

    /** Required when meals are offered: at least one dietary preference must be selected. */
    // Set by validate() so the parent can surface the ACTUAL failure reason
    // instead of assuming it was the dietary check.
    _validationMessage = '';

    @api
    get validationMessage() {
        return this._validationMessage;
    }

    @api
    validate() {
        if (this.offerMealsEnabled && this.selectedDietary.length === 0) {
            this.dietaryEnabled = true;
            this.dietaryError = 'Select at least one dietary preference (required when meals are offered).';
            this._validationMessage = 'Please select at least one dietary preference since meals are being offered.';
            return false;
        }
        this.dietaryError = '';
        // When the custom survey is on, enforce the questionnaire rules too:
        // every question needs a label and choice questions need >=2 options.
        // The builder surfaces its own inline errors and returns false.
        if (this.customSurveyEnabled) {
            const builder = this.template.querySelector('c-ken-questionnaire-builder');
            if (builder && typeof builder.validate === 'function' && !builder.validate()) {
                this._validationMessage = 'Please complete the survey questions — each needs a title and choice questions need at least 2 options.';
                return false;
            }
        }
        this._validationMessage = '';
        return true;
    }

    handleMealCellToggle(event) {
        const { dateKey, meal } = event.target.dataset;
        const checked = event.target.checked;
        const current = { ...(this.mealsByDate[dateKey] || {}) };
        if (checked) {
            current[meal] = true;
        } else {
            delete current[meal];
        }
        this.mealsByDate = { ...this.mealsByDate, [dateKey]: current };
        this.emitChange();
    }

    handleMealRowToggle(event) {
        const { dateKey } = event.target.dataset;
        const checked = event.target.checked;
        const current = {};
        if (checked) {
            MEAL_COLUMNS.forEach(meal => { current[meal] = true; });
        }
        this.mealsByDate = { ...this.mealsByDate, [dateKey]: current };
        this.emitChange();
    }

    handleMealsPaidToggle(event) {
        this.mealsPaidAddonEnabled = event.target.checked;
        this.emitChange();
    }

    /* ---------- Dietary ---------- */
    handleDietaryToggle(event) {
        this.dietaryEnabled = event.target.checked;
        if (!this.dietaryEnabled) {
            this.selectedDietary = [];
        }
        this.emitChange();
    }

    handleDietaryOptionChange(event) {
        const value = event.target.dataset.value;
        const checked = event.target.checked;
        if (checked) {
            if (!this.selectedDietary.includes(value)) {
                this.selectedDietary = [...this.selectedDietary, value];
            }
        } else {
            this.selectedDietary = this.selectedDietary.filter(v => v !== value);
        }
        if (this.selectedDietary.length > 0) {
            this.dietaryError = '';
        }
        this.emitChange();
    }

    /* ---------- Custom Survey ---------- */
    handleCustomSurveyToggle(event) {
        this.customSurveyEnabled = event.target.checked;
        if (this.customSurveyEnabled && (!this.surveyQuestions || !this.surveyQuestions.length)) {
            this.surveyQuestions = [
                {
                    id: `q-${Date.now()}`,
                    number: 1,
                    text: '',
                    type: 'Multiple Choice',
                    required: true,
                    options: [
                        { id: `opt-${Date.now()}-a`, text: '', letter: 'a' },
                        { id: `opt-${Date.now()}-b`, text: '', letter: 'b' }
                    ]
                }
            ];
        }
        this.emitChange();
    }

    handleQuestionsChange(event) {
        if (!event.detail || !Array.isArray(event.detail.questions)) {
            return;
        }
        this.surveyQuestions = event.detail.questions;
        this.emitChange();
    }

    /* ---------- Emit aggregated state ---------- */
    buildMealsByDate() {
        const out = {};
        Object.keys(this.mealsByDate || {}).forEach(dateKey => {
            const selected = this.mealsByDate[dateKey] || {};
            const meals = MEAL_COLUMNS.filter(meal => selected[meal]);
            if (meals.length) {
                out[dateKey] = meals;
            }
        });
        return out;
    }

    emitChange() {
        this.dispatchEvent(new CustomEvent('surveychange', {
            detail: {
                offerMealsEnabled: this.offerMealsEnabled,
                mealsByDate: this.buildMealsByDate(),
                mealsPaidAddonEnabled: this.offerMealsEnabled ? this.mealsPaidAddonEnabled : false,
                dietaryEnabled: this.offerMealsEnabled ? this.dietaryEnabled : false,
                dietaryOptions: this.offerMealsEnabled && this.dietaryEnabled ? [...this.selectedDietary] : [],
                customSurveyEnabled: this.customSurveyEnabled,
                surveyQuestions: this.customSurveyEnabled ? this.surveyQuestions : []
            },
            bubbles: true,
            composed: true
        }));
    }
}