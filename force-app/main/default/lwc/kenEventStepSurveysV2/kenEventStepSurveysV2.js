import { LightningElement, api } from 'lwc';

export default class KenEventStepSurveysV2 extends LightningElement {
    @api surveyMeals = false;
    @api surveyCustom = false;

    get mealsSwitchClass() { return this.surveyMeals ? 'switch switch--on' : 'switch'; }
    get customSwitchClass() { return this.surveyCustom ? 'switch switch--on' : 'switch'; }

    handleToggleMeals() {
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'surveyMeals', value: !this.surveyMeals } }));
    }
    handleToggleCustom() {
        this.dispatchEvent(new CustomEvent('valuechange', { detail: { field: 'surveyCustom', value: !this.surveyCustom } }));
    }
}