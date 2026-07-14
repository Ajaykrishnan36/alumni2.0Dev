import { NavigationMixin as navigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, updateRecord } from 'lightning/uiRecordApi';
import { LightningElement, api, track, wire } from 'lwc';
import TARGET_AUDIENCE from '@salesforce/schema/Ken_Event_Master__c.Target_Audience_Applicable__c';

const NOT_FOUND = -1;

export default class EventTargetAudience extends navigationMixin(LightningElement) {
  @api eventRecordId;
  @track audienceOptions = ['Students', 'Alumni', 'Faculty'];
  @track selectedValues = [];
  showSpinner = false;
  isInviteAll = false;

  @wire(getRecord, { fields: [TARGET_AUDIENCE], recordId: '$eventRecordId' })
  targetAudience({ error, data }) {
    if (data) {
      const { value } = data.fields.Target_Audience_Applicable__c;
      if (value) {
        this.selectedValues = value.split(';');
      } else {
        this.selectedValues = [];
      }
    } else if (error) {
      this.showToast('Error', 'Error retrieving target audience', 'error');
    }
  }

  get allVariant() {
    if (this.isInviteAll) {
      return 'brand';
    }
    return 'neutral';
  }

  get alumniVariant() {
    if (this.selectedValues.includes('Alumni')) {
      return 'brand';
    }
    return 'neutral';
  }

  get studentVariant() {
    if (this.selectedValues.includes('Students')) {
      return 'brand';
    }
    return 'neutral';
  }

  get facultyVariant() {
    if (this.selectedValues.includes('Faculty')) {
      return 'brand';
    }
    return 'neutral';
  }


  handleAudienceSelection(event) {
    const selected = event.target.dataset.value;
    this.toggleSelection(selected);
  }

  handleInviteAll() {
    this.isInviteAll = !this.isInviteAll;
    if (this.isInviteAll) {
      this.selectedValues = [...this.audienceOptions];
    } else {
      this.selectedValues = [];
    }
  }

  handleClick() {
    this.isInviteAll = !this.isInviteAll;
  }

  handlePrevious() {
    this.dispatchEvent(new CustomEvent("previous", { detail: "eventSetup" }));
  }

  async handleSave() {
    if (!this.eventRecordId) {
      this.showToast('Error', 'No event ID found', 'error');
      return;
    }

    this.showSpinner = true;

    try {
      await updateRecord({ fields: { 'Id': this.eventRecordId, [TARGET_AUDIENCE.fieldApiName]: this.selectedValues.join(';') } });
      this.showToast('Success', 'Target audience updated successfully', 'success');
      this.dispatchEvent(new CustomEvent("targetaudience", { detail: { eventId: this.eventRecordId } }));
    } catch  {
      this.showToast('Error', 'Error updating record', 'error');
    } finally {
      this.showSpinner = false;
    }
  }

  handleCancel() {
    if (this.eventRecordId) {
       this[navigationMixin.Navigate]({
        attributes: {
          actionName: "view",
          recordId: this.eventRecordId
        },
        type: "standard__recordPage"
      });
    } else {
      this[navigationMixin.Navigate]({
       attributes: {
          actionName: "list",
          objectApiName: "Ken_Event_Master__c"
        },
        state: {
          filterName: "Recent"
        },
        type: "standard__objectPage"
      });
    }
  }

  toggleSelection(option) {
    const index = this.selectedValues.indexOf(option);
    if (index === NOT_FOUND) {
      this.selectedValues = [...this.selectedValues, option];
    } else {
      this.selectedValues = this.selectedValues.filter(val => val !== option);
    }
  }

  showToast(successMessage, title, variant) {
    const toastEvent = new ShowToastEvent({
      message: successMessage,
      title,
      variant
    });
    this.dispatchEvent(toastEvent);
  }

}