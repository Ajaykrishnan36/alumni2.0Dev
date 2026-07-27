import { LightningElement, wire, api, track } from 'lwc';
import { NavigationMixin } from "lightning/navigation";
import getEventSessions from '@salesforce/apex/KenEventFormController.getEventSessions';
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import ID_FIELD from '@salesforce/schema/Ken_Event_Master__c.Id';
import EVENT_STATUS_FIELD from '@salesforce/schema/Ken_Event_Master__c.Event_Status__c';
import { updateRecord } from 'lightning/uiRecordApi';

export default class KenEventSummary extends NavigationMixin(LightningElement) {
  @api eventRecordId;
  @track sessions = [];
  @track eventFields = {
    eventFee: '',
    noFee: false,
    eventName: '',
    eventCoverImage: '',
    eventStartDate: null,
    eventEndDate: null,
    eventType: '',
    eventParticipants: '',
    eventDescription: '',
    eventStatus: ''
  };
  connectedCallback() {
    this.loadSessions();
  }
  @api
  loadSessions() {
    //this.isLoading = true;
    getEventSessions({ eventId: this.eventRecordId })

      .then(result => {
        this.sessions = result.map((record) => ({
          ...record,
          Start_Time__c: this.formatTime(record.Start_Time__c),
          End_Time__c: this.formatTime(record.End_Time__c),
        }));
        console.log('sessions--' + JSON.stringify(this.sessions));
        if (result.length > 0) {
          const eventRef = result[0].Event_Reference__r; // Access the related object
          this.eventFields.eventFee = eventRef.Event_Fee__c;
          this.eventFields.noFee = eventRef.No_Fee__c;
          this.eventFields.eventName = eventRef.Name;
          this.eventFields.eventCoverImage = eventRef.Event_banner__c;
          this.eventFields.eventStartDate = eventRef.Start_Date__c;
          this.eventFields.eventEndDate = eventRef.End_Date__c;
          this.eventFields.eventType = eventRef.Event_Type__c;
          this.eventFields.eventParticipants = eventRef.Max_Allowed_Participants__c;
          this.eventFields.eventDescription = eventRef.Description__c;
          this.eventFields.eventStatus = eventRef.Event_Status__c;
        }
      })
      .catch(error => {
        this.showToast('Error', 'Error fetching eventsessions', error.body.message);
        this.sessions = [];
        //this.isLoading = false;
      });
  }


  formatTime(isoString) {
    if (!isoString) return null;

    const date = new Date(isoString);
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false });
  }

  handleSummary() {
    const fields = {};
    fields[ID_FIELD.fieldApiName] = this.eventRecordId;
    // 'Submitted' is no longer used — submitting moves the event to Pending Approval (which both
    // triggers the approval process and keeps it visible in the hosted-events list).
    fields[EVENT_STATUS_FIELD.fieldApiName] = (this.eventFields.eventStatus == 'In Progress' || !this.eventFields.eventStatus)
        ? 'Pending Approval'
        : this.eventFields.eventStatus;

    const recordInput = { fields };

    updateRecord(recordInput)
      .then(() => {

        this[NavigationMixin.Navigate]({
          type: "standard__objectPage",
          attributes: {
            objectApiName: "Ken_Event_Master__c",
            actionName: "list"
          },
          state: {
            filterName: "Recent"
          }
        });

        setTimeout(() => {
          window.location.reload();
        }, 1000);

        this.dispatchEvent(new CloseActionScreenEvent());
      })
      .catch(error => {
        this.showToast('Error', 'Error updating event status', 'error');
        console.error('Error updating record:', error);
      });
  }

  handleCancel() {
    if (this.eventRecordId) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: this.eventRecordId,
          actionName: "view"
        }
      });
    } else {
      this[NavigationMixin.Navigate]({
        type: "standard__objectPage",
        attributes: {
          objectApiName: "Ken_Event_Master__c",
          actionName: "list"
        },
        state: {
          filterName: "Recent"
        }
      });
    }
  }

  handlePrevious() {

    this.dispatchEvent(new CustomEvent("previous", { detail: "feeSetup" }));
  }

  showToast(title, successMessage, variant) {
    const toastEvent = new ShowToastEvent({
      title: title,
      message: successMessage,
      variant: variant
    });
    this.dispatchEvent(toastEvent);
  }
}