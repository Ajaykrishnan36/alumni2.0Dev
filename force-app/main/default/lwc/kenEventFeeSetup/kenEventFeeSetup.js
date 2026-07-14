import { LightningElement, track, api, wire } from 'lwc';
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue  } from 'lightning/uiRecordApi';
//import insertFee from '@salesforce/apex/KenEventFormController.insertFee';
import EVENTNAME from "@salesforce/schema/Ken_Event_Master__c.Name";
import updateFee from '@salesforce/apex/KenEventFormController.updateFee';
import getEventSessions from '@salesforce/apex/KenEventFormController.getEventSessions';
export default class KenEventFeeSetup extends NavigationMixin (LightningElement) {
    @api eventRecordId;
    @api isEventWise;
    @api isSessionWise;
    @track eventName;
    @track eventFields ={
        eventFee:null,
        noFee:false,
        eventName:''
      };
    
    @track sessions = []; // Session data fetched from Apex
   @track sessionsByDate = [];
   
    connectedCallback() {
        this.loadSessions();
    }
  
    // Fetch the sessions from Apex
    
    loadSessions() {
        //this.isLoading = true;
        //if(this.isEventWise){
          getEventSessions({ eventId: this.eventRecordId})
            .then(result => {
              this.sessions = result.map((session, index) => ({
                ...session,
                displayIndex: index + 1 
            }));
              console.log('Inside getEventsSessions--'+this.sessions);

              /*const groupedData = {};

              result.forEach((session, index) => {
                  const dateKey = session.Start_Date__c.split('T')[0]; 
                  if (!groupedData[dateKey]) {
                      groupedData[dateKey] = {
                          formattedDate: new Date(dateKey).toLocaleDateString(),
                          sessions: []
                      };
                  }
                  groupedData[dateKey].sessions.push({
                      ...session,
                      displayIndex: groupedData[dateKey].sessions.length + 1
                  });
              });

              // Convert grouped data to an array for template iteration
              this.sessionsByDate = Object.keys(groupedData).map(date => ({
                  date,
                  formattedDate: groupedData[date].formattedDate,
                  sessions: groupedData[date].sessions
              }));

              // Calculate initial total cost
             // this.calculateTotalCost();
               /* this.sessions = result.map((session, index) => ({
                  ...session,
                  displayIndex: index + 1 
              }));*/
                //console.log('Inside getEventsSessions--'+this.sessions);
                if (result.length > 0 ) {
                  const eventRef = result[0].Event_Reference__r;
                  this.eventFields.eventFee = eventRef.Event_Fee__c;
                  this.eventFields.noFee = eventRef.No_Fee__c;
                  this.eventFields.eventName = eventRef.Name;
              }
            })
            .catch(error => {
                this.showErrorToast('Error fetching sessions', error.body.message);
                //this.isLoading = false;
            });
       // }
        
    }
   
    handleEventFeeChange(event) {
        //this.eventFee = event.detail.value;
        
        console.log('eventname--'+event.target.name);
        console.log('eventType---'+event.target.type);
        const field = event.target.name;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        console.log('value--'+value);
        //this.feeRecords[field]=value;
        if(field==='noFee'){
            this.eventFields.noFee = value;
            this.eventFields.eventFee = 0;
        }
        else if(field === 'eventFee'){
        
            this.eventFields.eventFee = value;
            this.eventFields.noFee = false;
          }
        //console.log(JSON.stringify(this.feeRecords));
    }

    handleSessionFeeChange(event) {
        const sessionId = event.target.dataset.id;
        //const sessionFee = event.detail.value;
        console.log('sessionId--'+sessionId);
        console.log('eventname--'+event.target.name);
        console.log('eventType---'+event.target.type);
        const fieldName = event.target.name;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        console.log('value---'+value);

        //Fee Validation
        const inputField = event.target;
        if (fieldName === 'Session_Fee__c' && value < 0) {
            inputField.setCustomValidity('Session Fee cannot be negative.');
        } else {
            inputField.setCustomValidity(''); // Clear the error if valid
        }
        
        inputField.reportValidity();

        //this.feeRecords[field]=value;
       /* this.sessionsByDate = this.sessionsByDate.map(sessionDate => ({
          ...sessionDate,
          sessions: sessionDate.sessions.map(session => {
              if (session.Id === sessionId) {
                  return {
                      ...session,
                      [fieldName]: value,
                      Session_Fee__c: fieldName === 'No_Fee__c' && value ? 0 : value,
                      //No_Fee__c: fieldName === 'Session_Fee__c'? false : true
                  };
              }
              return session;
          })
      }));*/

        console.log('Inside Fee change--'+this.sessions);
        this.sessions = this.sessions.map(session => {
            if (session.Id === sessionId) {
              return { ...session, [fieldName]: value,
                      Session_Fee__c: fieldName === 'No_Fee__c' && value ? 0 : value,
                      No_Fee__c: fieldName === 'Session_Fee__c' && value > 0 ? false : value
                    };
            }
            return session;
        });
    }

  /*  handleWholeDayFeeChange(event) {
      const dateId = event.target.dataset.id;
      const wholeDayFee = event.target.value;
      const fieldName = event.target.name;
      if(fieldName === 'Whole_Day_Fee__c'){
        this.sessionsByDate = this.sessionsByDate.map(sessionDate => {
          if (sessionDate.date === dateId) {
              return {
                  ...sessionDate,
                  wholeDayFee: wholeDayFee,
                  sessions: sessionDate.sessions.map(session => ({
                      ...session,
                      Session_Fee__c: wholeDayFee,
                      No_Fee__c: false, 
                  }))
              };
          }
          return sessionDate;
      });
      }else if(fieldName === 'No_Fee__c'){
        this.sessionsByDate = this.sessionsByDate.map(sessionDate => {
          if (sessionDate.date === dateId) {
              return {
                  ...sessionDate,
                  wholeDayFee: wholeDayFee,
                  sessions: sessionDate.sessions.map(session => ({
                      ...session,
                      Session_Fee__c: 0,
                      No_Fee__c: true, 
                  }))
              };
          }
          return sessionDate;
      });
      }
      
  }*/
    // Handle save
    handleSave() {
        if (this.isEventWise) {
            // Call the unified Apex method for event-wise fee
            if(this.eventFields.eventFee < 0){
                this.showToast('Validation Error', 'Event Fee cannot be negative. Please correct it before submitting.', 'error');
                return;
            }
            updateFee({ 
                isEventWise: true, 
                eventId: this.eventRecordId, 
                eventFee: this.eventFields.eventFee, 
                isNoFee: this.eventFields.noFee, 
                sessionsMap: null // No need to pass session data for event-wise 
            })
                .then(() => {
                  //this.isEventWise = false;
                  this.dispatchEvent(new CustomEvent('feesetup', { detail: { eventId: this.eventRecordId } }));
                })
                .catch(error => {
                    // Handle error
                    this.showToast('Error fetching sessions', error.body.message, 'error');
                });
        } else if (this.isSessionWise) {

            // Validate session fees from sessionsMap (this.sessions)
            const invalidSession = this.sessions.find(session => session.Session_Fee__c < 0);
            if (invalidSession) {
                this.showToast('Validation Error', 'Session Fee cannot be negative. Please correct it before submitting.', 'error');
                return;
            }
            // Prepare sessionsMap to pass to Apex
            const sessionsMap = [];
            //const additionalData = 'check';
            /*this.sessionsByDate.forEach(session => {
                sessionsMap.push(session.sessions);
            });*/
            console.log('Inside save this.sessions'+this.sessionsByDate.flatMap(event => event.sessions));
            // Call the unified Apex method for session-wise fee
            updateFee({ 
                isEventWise: false, 
                eventId: this.eventRecordId, 
                eventFee: null, // No need to pass event fee for session-wise 
                isNoFee: this.eventNoFee, 
                sessionsMap: this.sessions
            })
                .then(() => {
                  //this.isSessionWise = false;
                  //this.callChildComponentMethod();
                  
                  this.dispatchEvent(new CustomEvent('feesetup', { detail: { eventId: this.eventRecordId } }));
                })
                .catch(error => {
                    // Handle error
                    this.showToast('Error fetching sessions', error.body.message, 'error');
                });
        }
    }
      @wire(getRecord, { recordId: '$eventRecordId', fields: [EVENTNAME] })
      wiredRecord({ data }) {
          if (data) {
              this.eventName = getFieldValue(data, EVENTNAME);
          }
        
      }

      callChildComponentMethod() {
        setTimeout(() => {
            const childComponent = this.template.querySelector('c-event-summary');
            if (childComponent) {
                childComponent.loadSessions(); 
            } else {
                console.error('Child component not found!');
            }
        }, 0);
    }

      handleinputChange(event) {
        //console.log(JSON.stringfy(event));
        console.log(event.target.value);
        console.log(event.target.name);
        console.log(event.target.type);
        const field = event.target.name;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value; // Handle checkbox differently
  
  
       this.feeRecords[field]=value;
      
          console.log(JSON.stringify(this.feeRecords));
    }
    handlePreviousFee() {
          this.isEventWise =false;
          this.isSessionWise = false;
        this.dispatchEvent(new CustomEvent("previous", { detail: "scheduleSetup" }));
      }

    
      showToast(title, message, variant) {
        const toastEvent = new ShowToastEvent({
          title: title,
          message: message,
          variant: variant
        });
        this.dispatchEvent(toastEvent);
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
}