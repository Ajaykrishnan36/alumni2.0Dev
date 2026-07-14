import { LightningElement, api, wire } from 'lwc';
import fetchLookupData from '@salesforce/apex/KenCustomLookupLwcController.fetchLookupData';

const DELAY = 300; // delay for Apex callout in milliseconds

export default class KenCustomLookupLwc extends LightningElement {
    @api label = 'Event Master Lookup';
    @api placeholder = 'Search Event...';
    @api iconname ='';
    @api sobjectapiname =''; // Use Event_Master__c as the sObject API name
    @api recordtypename ='';

    lstResult = []; // list of search results
    hasRecords = true;
    searchKey = ''; // stores the search input
    isSearchLoading = false; // controls the loading spinner
    delayTimeout;
    selectedRecord = {}; // store selected lookup record

    // wire function to fetch search records based on user input
    @wire(fetchLookupData, { searchKey: '$searchKey', sObjectApiName: '$sobjectapiname', recordTypeName: '$recordtypename' })
    searchResult({ data, error }) {
        this.isSearchLoading = false;
        if (data) {
            this.hasRecords = data.length > 0;
            this.lstResult = data;
        } else if (error) {
            console.log('Error fetching lookup data: ', error);
        }
    }

    // update searchKey property on input field change
    handleKeyChange(event) {
        this.isSearchLoading = true;
        window.clearTimeout(this.delayTimeout);
        const searchKey = event.target.value;
        this.delayTimeout = setTimeout(() => {
            this.searchKey = searchKey;
        }, DELAY);
    }

    // method to toggle the lookup result section
    toggleResult(event) {
        const lookupInputContainer = this.template.querySelector('.lookupInputContainer');
        const clsList = lookupInputContainer.classList;
        const whichEvent = event.target.getAttribute('data-source');
        switch (whichEvent) {
            case 'searchInputField':
                clsList.add('slds-is-open');
                break;
            case 'lookupContainer':
                clsList.remove('slds-is-open');
                break;
        }
    }

    // method to clear the selected lookup record
    handleRemove() {
        this.searchKey = '';
        this.selectedRecord = {};
        this.lookupUpdatehandler(undefined);

        // remove selected pill and display input field again
        const searchBoxWrapper = this.template.querySelector('.searchBoxWrapper');
        searchBoxWrapper.classList.remove('slds-hide');
        searchBoxWrapper.classList.add('slds-show');

        const pillDiv = this.template.querySelector('.pillDiv');
        pillDiv.classList.remove('slds-show');
        pillDiv.classList.add('slds-hide');
    }

    // method to update the selected record from search results
    handelSelectedRecord(event) {
        const objId = event.target.getAttribute('data-recid');
        this.selectedRecord = this.lstResult.find((data) => data.Id === objId);
        this.lookupUpdatehandler(this.selectedRecord);
        this.handelSelectRecordHelper();
    }

    // helper method to show/hide lookup result container on UI
    handelSelectRecordHelper() {
        this.template.querySelector('.lookupInputContainer').classList.remove('slds-is-open');

        const searchBoxWrapper = this.template.querySelector('.searchBoxWrapper');
        searchBoxWrapper.classList.remove('slds-show');
        searchBoxWrapper.classList.add('slds-hide');

        const pillDiv = this.template.querySelector('.pillDiv');
        pillDiv.classList.remove('slds-hide');
        pillDiv.classList.add('slds-show');
    }

    // send selected lookup record to the parent component using custom event
    lookupUpdatehandler(value) {
        const oEvent = new CustomEvent('lookupupdate', {
            detail: { selectedRecord: value },
        });
        this.dispatchEvent(oEvent);
    }
}