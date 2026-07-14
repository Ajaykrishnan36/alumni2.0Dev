/*
==========================================
    Title: SLDS Select
    Purpose: Displays a set of passed in 
        picklist values.
    Author: Clay Phillips
    Date: 05/04/2020 
==========================================
*/

import {LightningElement, api} from 'lwc';

export default class QSelect extends LightningElement{
    // Public variables
    @api picklistName = 'sldsSelect';
    @api picklistLabel = 'SLDS Select';
    @api picklistValues = [
        {
            apiName: 'valueOne',
            label: 'Value One'
        },
        {
            apiName: 'valueTwo',
            label: 'Value Two'
        },
        {
            apiName: 'valueThree',
            label: 'Value Three'
        },
        {
            apiName: 'valueFour',
            label: 'Value Four'
        },
        {
            apiName: 'valueFive',
            label: 'Value Five'
        }
    ];
    @api showEmptyOption;

    @api 
    get isDisabled(){
        return this._isDisabled;
    }
    set isDisabled(value){
        this._isDisabled = value;
        if(this.componentRendered === true){
            this.enableDisablePicklist();
        }
    }
    // private variable for public isDisabled variable
    _isDisabled = false;

    @api isRequired = false;
    @api helpText;

    // Control the event capture and bubble phase settings when a value is selected
    @api eventBubbles = false;
    @api eventComposed = false;

    renderedCallback(){
        if(this.componentRendered === false){
            this.enableDisablePicklist();
            this.componentRendered = true;
        }
    }

    enableDisablePicklist(){
        if(this.isDisabled === true){
            this.template.querySelector('select').disabled = true;
        }
        else{
            this.template.querySelector('select').disabled = false;
        }
    }

    selectValue(event){
        let detail = {};
        detail.value = event.target.value;
        let selectHTML = this.template.querySelector('select');
        detail.label = selectHTML.options[selectHTML.selectedIndex].innerHTML; // grabs the displayed value

        //console.log('detail.label: ' + detail.label);

        const selectPicklistValueEvent = new CustomEvent('selectpicklistvalueevent',
        {
            detail: detail,
            bubbles: this.eventBubbles,
            composed: this.eventComposed
        });
        this.dispatchEvent(selectPicklistValueEvent);
    }
}