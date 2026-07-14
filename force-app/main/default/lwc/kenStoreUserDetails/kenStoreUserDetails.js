import { LightningElement,wire } from 'lwc';
import Id from '@salesforce/user/Id';
import { getRecord } from 'lightning/uiRecordApi';
import ACCOUNT_ID from '@salesforce/schema/User.AccountId';
import FIRST_NAME from '@salesforce/schema/Account.FirstName';
import LAST_NAME from '@salesforce/schema/Account.LastName';
import EMAIL from '@salesforce/schema/Account.PersonEmail';

export default class KenStoreUserDetails extends LightningElement {
    initial = true;
    userId = Id;
    accountId;

    @wire(getRecord, { recordId: '$userId', fields: [ACCOUNT_ID]})
    getUserDetails({ error, data }) {
        if (error) {
            console.log(error);
        } else if (data) {
            this.accountId = data.fields.AccountId.value;
            sessionStorage.setItem('accountId', this.accountId);
        }
    }

    @wire(getRecord, { recordId: '$accountId', fields: [FIRST_NAME, LAST_NAME, EMAIL]})
    getAccountDetails({ error, data }) {
        if (error) {
            console.log(error);
        } else if (data) {
            sessionStorage.setItem('accountFirstName', data.fields.FirstName.value);
            sessionStorage.setItem('accountLastName', data.fields.LastName.value);
            sessionStorage.setItem('accountEmail', data.fields.PersonEmail.value);
        }
    }


    renderedCallback() {
        if (this.initial){
            this.initial = false;
            sessionStorage.setItem("userId",this.userId);
        }
            
    }
}