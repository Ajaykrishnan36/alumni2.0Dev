import { LightningElement, api } from 'lwc';

export default class KenSurveyResultsV2 extends LightningElement {
    @api survey = {};

    get title() { return this.survey && this.survey.title; }

    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
}